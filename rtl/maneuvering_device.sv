module maneuvering_device (
    input clk,
    input wire [15:0] mister_joystick,
    input wire [15:0] mister_joystick_analog,
    input wire [24:0] mister_mouse,
    input rts,
    input overclock,
    bytestream.source serial_out
);

    // The baud rate of spoon is 1200
    // A serial frame costs 1 start bit, 8 data bits and 1 stop bit
    // In truth according to the documentation these are 7 data bits and 2 stop bits
    // But I know that this is just wrong documentation.
    // 1200 baud is eqivalent to 120 byte/s
    // 30e6 / 120 is 250000
    // For overclocking: 30e6 / 50 Hz video / 3 = 200000
    wire [18:0] kTicksPerByte = overclock ? 200000 : 250000;

    typedef enum bit [1:0] {
        DEVICE_ID,  // Always start with this after RTS is asserted
        BYTE0,  // 1 1 B1 B2 Y7 Y6 X7 X6
        BYTE1,  // 1 0 X5 X4 X3 X2 X1 X0
        BYTE2  // 1 0 Y5 Y4 Y3 Y2 Y1 Y0
    } e_state;

    e_state state;
    bit [18:0] cnt;
    bit [7:0] frame[3];

    bit perform_transmit;

    //wire b1 = mister_joystick[5];
    //wire b2 = mister_joystick[4];

    wire b1 = mister_mouse[0];
    wire b2 = mister_mouse[1];

    bit b1_q, b2_q;

    bit signed [7:0] speed;

    bit signed [7:0] x_analog;
    bit signed [7:0] y_analog;

    bit signed [7:0] x;
    bit signed [7:0] y;

    bit signed [7:0] x_q;
    bit signed [7:0] y_q;
    bit [3:0] accel;

    bit mouse_event_prev;
    wire mouse_event = mister_mouse[24];

    bit signed [8:0] mouse_x;
    bit signed [8:0] mouse_y;

    wire mouse_button_left = mister_mouse[0];
    wire mouse_button_right = mister_mouse[1];

    always_comb begin
        x = 0;
        y = 0;

        // The spoon has a short amount of time where it moves 2 ticks per frame
        // After a while it switches itself to 8 ticks per frame
        // We are overclocking the spoon, changing 8 to 2 and 2 to 1
        if (accel >= 5) begin
            speed = overclock ? 7 : 8;
        end else begin
            speed = overclock ? 2 : 2;
        end

        if (mister_joystick[0]) x = speed;
        if (mister_joystick[2]) y = speed;
        if (mister_joystick[1]) x = -speed;
        if (mister_joystick[3]) y = -speed;

        x_analog = mister_joystick_analog[7:0];
        y_analog = mister_joystick_analog[15:8];
        x_analog = (x_analog + 4) / 8;
        y_analog = (y_analog + 4) / 8;
        if (x_analog != 0) x = x_analog;
        if (y_analog != 0) y = y_analog;

        mouse_x = {mister_mouse[4],mister_mouse[15:8]};
        mouse_y = -{mister_mouse[5],mister_mouse[23:16]};

        // FIXME: mouse speed should be accumulated, not directly set
        x = mouse_x;
        y = mouse_y;

        // Only transmit when buttons have changed or when we are moving the cursor
        // Even so, the speed is not changed, we must transmit permanently.
        perform_transmit = (b1 != b1_q) || (b2 != b2_q) || (x != x_q) || (y != y_q) || (mouse_event != mouse_event_prev);
    end

    always_ff @(posedge clk) begin
        if (serial_out.write) $display("INPUT SERIAL %x", serial_out.data);
    end
    always_ff @(posedge clk) begin
        serial_out.write <= 0;

        if (rts) begin
            state <= DEVICE_ID;
            cnt   <= kTicksPerByte;
        end else if (cnt != 0) begin
            cnt <= cnt - 1;
        end else begin
            cnt <= kTicksPerByte;

            case (state)
                DEVICE_ID: begin
                    //serial_out.data <= 8'hCA; // maneuvering
                    serial_out.data <= 8'hCD; // relative
                    state <= BYTE0;
                    serial_out.write <= 1;

                end
                BYTE0: begin
                    if (perform_transmit) begin
                        serial_out.data <= frame[0];
                        state <= BYTE1;
                        serial_out.write <= 1;

                        // store for next comparsion
                        x_q <= x;
                        y_q <= y;
                        b1_q <= b1;
                        b2_q <= b2;
                        mouse_event_prev <= mouse_event;
                    end
                end
                BYTE1: begin
                    serial_out.data <= frame[1];
                    state <= BYTE2;
                    serial_out.write <= 1;

                end
                BYTE2: begin
                    serial_out.data <= frame[2];
                    state <= BYTE0;
                    serial_out.write <= 1;

                end
            endcase
        end


        // change whole frame at the same time before transmitting the next
        if (cnt == 10 && state == BYTE0) begin
            frame[0] <= {2'b11, b1, b2, y[7:6], x[7:6]};
            frame[1] <= {2'b10, x[5:0]};
            frame[2] <= {2'b10, y[5:0]};

            if (mister_joystick[3:0] == 0) begin
                accel <= 0;
            end else if (mister_joystick[3:0] != 0 && accel < 7) begin
                accel <= accel + 1;
            end
        end
    end
endmodule

