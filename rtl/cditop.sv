
module cditop (
    input clk30,
    input reset,

    input tvmode_pal,
    input debug_uart_loopback,
    input debug_uart_fake_space,

    input scandouble,

    output bit ce_pix,

    output bit HBlank,
    output bit HSync,
    output bit VBlank,
    output bit VSync,

    output [7:0] r,
    output [7:0] g,
    output [7:0] b,

    output [24:0] sdram_addr,
    output        sdram_rd,
    output        sdram_wr,
    output        sdram_word,
    output [15:0] sdram_din,
    input  [15:0] sdram_dout,
    input         sdram_busy,
    output        sdram_burst,
    output        sdram_refresh,
    input         sdram_burstdata_valid,

    output scc68_uart_tx,
    input  scc68_uart_rx,

    input [12:0] slave_worm_adr,
    input [7:0] slave_worm_data,
    input slave_worm_wr,

    bytestream.source slave_serial_out,
    bytestream.sink slave_serial_in,
    output slave_rts
);

    parallelel_spi slave_servo_spi ();

    wire write_strobe;
    wire as;
    (* keep *) wire lds;
    (* keep *) wire uds;

    (* keep *) bit bus_ack  /*verilator public_flat_rd*/;

    (* keep *) bit [15:0] data_in;
    wire [15:0] cpu_data_out;
    (* keep *) wire [23:1] addr;
    wire [23:0] addr_byte = {addr[23:1], 1'b0};

    // 8 kB of NVRAM
    bit [7:0] nvram[8192]  /*verilator public_flat_rw*/;

    wire mcd212_bus_ack;
    wire [15:0] mcd212_dout;
    wire [15:0] cdic_dout;
    bit cdic_bus_ack;

    bit [7:0] nvram_readout;
    bit nvram_bus_ack;

    wire attex_cs_mcd212 = ((addr_byte <= 24'h27ffff) || (addr_byte >= 24'h400000)) && as && !addr[23];
    wire attex_cs_cdic = addr_byte[23:16] == 8'h30 && as;
    wire attex_cs_slave = addr_byte[23:16] == 8'h31 && as;
    wire attex_cs_nvram = addr_byte[23:16] == 8'h32 && as;

    bit [15:0] data_in_q = 0;
    bit attex_cs_slave_q = 0;

    wire bus_err_ram_area1 = (addr_byte >= 24'h600000 && addr_byte < 24'hd00000);
    wire bus_err_ram_area2 = (addr_byte >= 24'hf00000);
    wire bus_err = (bus_err_ram_area1 || bus_err_ram_area2) && as && (lds || uds);

    always_ff @(posedge clk30) begin
        data_in_q <= data_in;

        if (reset) ce_pix <= 0;
        else ce_pix <= !ce_pix;

        if (bus_ack) begin
            if ((lds || uds) && attex_cs_cdic && write_strobe)
                $display(
                    "Write CDIC %x %x %d %d %d", addr_byte, cpu_data_out, lds, uds, write_strobe
                );

            if ((lds || uds) && attex_cs_cdic && !write_strobe)
                $display("Read CDIC %x %x %d %d %d", addr_byte, data_in, lds, uds, write_strobe);

            if ((lds || uds) && attex_cs_slave && write_strobe)
                $display(
                    "Write SLAVE %x %x %d %d %d", addr[7:1], cpu_data_out, lds, uds, write_strobe
                );

            if ((lds || uds) && attex_cs_slave && !write_strobe)
                $display("Read SLAVE %x %x %d %d %d", addr[7:1], data_in_q, lds, uds, write_strobe);


            if ((lds || uds) && attex_cs_nvram)
                $display(
                    "Access NVRAM %x %x %x %d %d %d",
                    addr[7:1],
                    data_in_q,
                    cpu_data_out,
                    lds,
                    uds,
                    write_strobe
                );

        end
    end


    mcd212 mcd212_inst (
        .clk(clk30),
        .reset,
        .cpu_address(addr[22:1]),
        .cpu_din(cpu_data_out),
        .cpu_dout(mcd212_dout),
        .cpu_bus_ack(mcd212_bus_ack),
        .cpu_uds(uds),
        .cpu_lds(lds),
        .cpu_write_strobe(write_strobe),
        .cs(attex_cs_mcd212),
        .r(r),
        .g(g),
        .b(b),
        .hsync(HSync),
        .vsync(VSync),
        .hblank(HBlank),
        .vblank(VBlank),
        .sdram_addr(sdram_addr),
        .sdram_rd(sdram_rd),
        .sdram_wr(sdram_wr),
        .sdram_word(sdram_word),
        .sdram_din(sdram_din),
        .sdram_dout(sdram_dout),
        .sdram_busy(sdram_busy),
        .sdram_burst(sdram_burst),
        .sdram_refresh(sdram_refresh),
        .sdram_burstdata_valid
    );

    cdic cdic_inst (
        .clk(clk30),
        .reset,
        .address(addr),
        .din(cpu_data_out),
        .dout(cdic_dout),
        .uds(uds),
        .lds(lds),
        .write_strobe(write_strobe),
        .cs(attex_cs_cdic),
        .bus_ack(cdic_bus_ack)
    );

    wire vsdc_intn = 1'b1;
    wire in2in;

`ifndef DISABLE_MAIN_CPU
    scc68070 scc68070_0 (
        .clk(clk30),
        .reset(reset),  // External sync reset on emulated system
        .write_strobe,
        .as,
        .lds,
        .uds,
        .bus_ack(bus_ack),
        .bus_err,
        .int1(!vsdc_intn),
        .int2(1'b0),  // unconnected in CDi MONO1
        .in2(!in2in),
        .in4(1'b0),
        .in5(1'b0),
        .data_in(data_in),
        .data_out(cpu_data_out),
        .addr,
        .uart_tx(scc68_uart_tx),
        .uart_rx(scc68_uart_rx),
        .debug_uart_loopback,
        .debug_uart_fake_space
    );
`endif

    wire stand = !tvmode_pal;  // 1 NTSC, 0 PAL

    bit [7:0] ddra;
    bit [7:0] ddrb;
    bit [7:0] ddrc;

    bit quirk_force_mode_fault;
    wire [7:0] porta_in = cpu_data_out[7:0];
    bit [7:0] porta_out;
    wire [7:0] portb_in = 8'hff;
    bit [7:0] portb_out;
    wire [7:0] portc_in = {stand, 5'b11111, addr[2:1]};
    bit [7:0] portc_out;
    wire [7:0] portd_in = {!write_strobe, 7'b1111111};

    (* keep *) bit slave_bus_ack;

    always_comb begin
        bus_ack = 1;
        data_in = 0;

        if (attex_cs_slave) begin
            data_in = {porta_out, porta_out};
            bus_ack = slave_bus_ack;
        end else if (attex_cs_cdic) begin
            data_in = cdic_dout;
            bus_ack = cdic_bus_ack;
        end else if (attex_cs_nvram) begin
            data_in = {nvram_readout, nvram_readout};
            bus_ack = nvram_bus_ack || write_strobe;
        end else if (attex_cs_mcd212) begin
            data_in = mcd212_dout;
            bus_ack = mcd212_bus_ack;
        end
    end

    always_ff @(posedge clk30) begin

        if (attex_cs_nvram) begin
            if (uds && write_strobe) begin
                nvram[addr[13:1]] <= cpu_data_out[15:8];
            end else begin
                nvram_readout <= nvram[addr[13:1]];

                if (nvram_bus_ack) nvram_bus_ack <= 0;
                else nvram_bus_ack <= 1;
            end
        end

    end

    wire resetsys = ddrc[2] ? portc_out[2] : 1'b1;
    wire disdat_from_uc = ddrc[3] ? portc_out[3] : 1'b1;
    wire disdat_to_ic;

    wire disdat = disdat_from_uc && disdat_to_ic;
    wire disclk = ddrc[4] ? portc_out[4] : 1'b1;

    wire dtackslaven = ddrb[6] ? portb_out[6] : 1'b1;
    assign slave_rts = ddrb[4] ? portb_out[4] : 1'b1;
    assign in2in = ddrb[5] ? portb_out[5] : 1'b1;

    bit dtackslaven_q = 0;
    bit in2in_q = 1;

    (* keep *) bit slave_irq;
    bit [7:0] irq_cooldown = 0;

`ifndef DISABLE_SLAVE_UC
    uc68hc05 uc68hc05_0 (
        .clk30,
        .reset(reset),
        .porta_in,
        .porta_out,
        .portb_in,
        .portb_out,
        .portc_in({portc_in[7:5], disclk, disdat_to_ic, portc_in[2:0]}),
        .portc_out,
        .portd_in,
        .irq(!slave_irq),
        .ddra,
        .ddrb,
        .ddrc,

        .worm_adr (slave_worm_adr),
        .worm_data(slave_worm_data),
        .worm_wr  (slave_worm_wr),

        .serial_in(slave_serial_in),
        .serial_out(slave_serial_out),
        .spi(slave_servo_spi),
        .quirk_force_mode_fault(quirk_force_mode_fault)
    );
`endif

    u3090mg u3090mg (
        .clk(clk30),
        .sda_in(disdat_from_uc),
        .sda_out(disdat_to_ic),
        .scl(disclk)
    );

    servo_hle servo (
        .clk(clk30),
        .spi(slave_servo_spi),
        .quirk_force_mode_fault
    );

    always_comb begin
        slave_bus_ack = dtackslaven && !dtackslaven_q;
        slave_irq = irq_cooldown == 1;
    end

    always_ff @(posedge clk30) begin
        if (reset) begin
            irq_cooldown <= 0;
            attex_cs_slave_q <= 0;
            dtackslaven_q <= 0;
            in2in_q <= 1;
        end else begin
            attex_cs_slave_q <= attex_cs_slave;
            dtackslaven_q <= dtackslaven;
            in2in_q <= in2in;

            if (!in2in && in2in_q) $display("SLAVE IRQ2 1");
            if (in2in && !in2in_q) $display("SLAVE IRQ2 0");

            if (attex_cs_slave && !attex_cs_slave_q) irq_cooldown <= 40;
            else if (irq_cooldown != 0) irq_cooldown <= irq_cooldown - 1;
        end

    end

endmodule
