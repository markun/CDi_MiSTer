// Include common routines
#include <verilated.h>
#include <verilated_fst_c.h>
#include <verilated_vcd_c.h>

// Include model header, generated from Verilating "top.v"
#include "Vemu.h"
#include "Vemu___024root.h"

#include <chrono>
#include <csignal>
#include <cstdint>
#include <png.h>

#include "hle.h"
#include <byteswap.h>

typedef VerilatedFstC tracetype_t;

uint64_t sim_time = 0;

static bool do_trace{true};

volatile sig_atomic_t status = 0;

static void catch_function(int signo) {
    status = signo;
}
const int width = 120 * 16;
const int height = 312;
const int size = width * height * 3;

uint8_t output_image[size] = {0};

void write_png_file(const char *filename) {
    int y;

    FILE *fp = fopen(filename, "wb");
    if (!fp)
        abort();

    png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png)
        abort();

    png_infop info = png_create_info_struct(png);
    if (!info)
        abort();

    if (setjmp(png_jmpbuf(png)))
        abort();

    png_init_io(png, fp);

    // Output is 8bit depth, RGBA format.
    png_set_IHDR(png, info, width, height, 8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT,
                 PNG_FILTER_TYPE_DEFAULT);
    png_write_info(png, info);

    png_bytepp row_pointers = (png_bytepp)png_malloc(png, sizeof(png_bytepp) * height);

    for (int i = 0; i < height; i++) {
        row_pointers[i] = &output_image[width * 3 * i];
    }

    png_write_image(png, row_pointers);
    png_write_end(png, NULL);

    free(row_pointers);

    fclose(fp);

    png_destroy_write_struct(&png, &info);
}

void clock(tracetype_t &m_trace, Vemu &dut) {

    for (int i = 0; i < 2; i++) {
        dut.rootp->emu__DOT__clk_sys = (sim_time & 1);
        dut.eval();
        if (do_trace) {
            m_trace.dump(sim_time);
        }
        sim_time++;
    }
}

void loadfile(uint16_t index, const char *path, tracetype_t &m_trace, Vemu &dut) {

    FILE *f = fopen(path, "rb");
    assert(f);

    uint16_t transferword;

    dut.rootp->emu__DOT__ioctl_addr = 0;
    dut.rootp->emu__DOT__ioctl_index = index;

    // make some clocks before starting
    for (int y = 0; y < 300; y++) {
        clock(m_trace, dut);
    }

    while (fread(&transferword, 2, 1, f) == 1) {
        dut.rootp->emu__DOT__ioctl_wr = 1;
        dut.rootp->emu__DOT__ioctl_dout = transferword;

        clock(m_trace, dut);
        dut.rootp->emu__DOT__ioctl_wr = 0;

        // make some clocks to avoid asking for busy
        // the real MiSTer has 31 clocks between writes
        // we are going for ~20 to put more stress on it.
        for (int i = 0; i < 20; i++) {
            clock(m_trace, dut);
        }
        dut.rootp->emu__DOT__ioctl_addr += 2;
        clock(m_trace, dut);
    }
    fclose(f);
}

template <typename T, typename U> constexpr T BIT(T x, U n) noexcept {
    return (x >> n) & T(1);
}

void printstate(Vemu &dut) {

    static uint32_t regfile[16];

    uint32_t pc = dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__exe_pc;
    // d0 = dut.rootp->fx68k_tb__DOT__d0;
    memcpy(regfile, &dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__regfile[0],
           sizeof(regfile));

    printf("%x", pc);
    for (int i = 0; i < 16; i++)
        printf(" %x", regfile[i]);
    printf("\n");
}

// got from mame
uint32_t lba_from_time(uint32_t m_time) {
    const uint8_t bcd_mins = (m_time >> 24) & 0xff;
    const uint8_t mins_upper_digit = bcd_mins >> 4;
    const uint8_t mins_lower_digit = bcd_mins & 0xf;
    const uint8_t raw_mins = (mins_upper_digit * 10) + mins_lower_digit;

    const uint8_t bcd_secs = (m_time >> 16) & 0xff;
    const uint8_t secs_upper_digit = bcd_secs >> 4;
    const uint8_t secs_lower_digit = bcd_secs & 0xf;
    const uint8_t raw_secs = (secs_upper_digit * 10) + secs_lower_digit;

    uint32_t lba = ((raw_mins * 60) + raw_secs) * 75;

    const uint8_t bcd_frac = (m_time >> 8) & 0xff;
    const bool even_second = BIT(bcd_frac, 7);
    if (!even_second) {
        const uint8_t frac_upper_digit = bcd_frac >> 4;
        const uint8_t frac_lower_digit = bcd_frac & 0xf;
        const uint8_t raw_frac = (frac_upper_digit * 10) + frac_lower_digit;
        lba += raw_frac;
    }

    if (lba >= 150)
        lba -= 150;

    return lba;
}

void do_justwait(tracetype_t &m_trace, Vemu &dut) {
    dut.eval();
    do_trace = false;
    dut.rootp->emu__DOT__debug_uart_fake_space = false;
    dut.rootp->emu__DOT__tvmode_ntsc = false;

    // FILE *f_cd_bin = fopen("images/Zelda Wand of Gamelon.bin", "rb");
    FILE *f_cd_bin = fopen("images/FROG.BIN", "rb");
    assert(f_cd_bin);

    dut.RESET = 1;
    dut.UART_RXD = 1;

    // wait for SDRAM to initialize
    for (int y = 0; y < 300; y++) {
        clock(m_trace, dut);
    }

    /*
    dut.rootp->emu__DOT__ioctl_download = 1;
    loadfile(0, "cdi200.rom", m_trace, dut);
    loadfile(0x0040, "zx405042p__cdi_slave_2.0__b43t__zzmk9213.mc68hc705c8a_withtestrom.7206", m_trace, dut);
    dut.rootp->emu__DOT__ioctl_download = 0;
    */
    dut.RESET = 0;
    auto start = std::chrono::system_clock::now();

    int sd_rd_q;
    static constexpr uint32_t kSectorHeaderSize{12};
    static constexpr uint32_t kSectorSize{0x930};

    uint16_t sector_buffer[0x1000];
    uint16_t sector_buffer_index = 0;

    // for (int y = 0; y < 780000; y++) {
    for (int y = 0;; y++) {
        clock(m_trace, dut);

        if ((y % 100000) == 0) {
            printf("%d\n", y);
        }

        // Abort on illegal Instructions
        if (dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__trap_illegal) {
            fprintf(stderr, "Illegal Instruction!\n");
            break;
        }

        // Simulate CD data delivery from HPS
        if (dut.rootp->emu__DOT__sd_rd && sd_rd_q == 0) {
            assert(dut.rootp->emu__DOT__sd_ack == 0);
            dut.rootp->emu__DOT__sd_ack = 1;

            uint32_t lba = dut.rootp->emu__DOT__sd_lba0;
            uint32_t m_time = dut.rootp->emu__DOT__cditop__DOT__cdic_inst__DOT__time_register;

            uint32_t reference_lba = lba_from_time(m_time);
            // assert(lba == reference_lba);

            uint32_t file_offset = (lba - 150) * kSectorSize;

            printf("Request Sector %x %x\n", m_time, lba, file_offset);

            int res = fseek(f_cd_bin, file_offset, SEEK_SET);
            assert(res == 0);

            fread(sector_buffer, 1, 0x930, f_cd_bin);
            sector_buffer_index = 0;
        }

        dut.rootp->emu__DOT__sd_buff_wr = 0;
        if (dut.rootp->emu__DOT__sd_ack && (y & 0xf) == 0) {
            if (sector_buffer_index == kSectorSize / 2) {
                dut.rootp->emu__DOT__sd_ack = 0;
                printf("Sector transferred!\n");
            } else {
                dut.rootp->emu__DOT__sd_buff_dout = sector_buffer[sector_buffer_index];
                dut.rootp->emu__DOT__sd_buff_wr = 1;
                sector_buffer_index++;
            }
        }

        sd_rd_q = dut.rootp->emu__DOT__sd_rd;

        /*
        if (dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__uart_transmit_holding_valid) {
            fputc(dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__uart_transmit_holding_register, stderr);
            dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__uart_transmit_holding_valid = 0;
        }
        */
        static uint32_t print_instructions = 0;
        static uint32_t prevpc = 0;
        static uint32_t leave_sys_callpc = 0;

        // Trace System Calls
        if (dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__decodeopc &&
            dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__clkena_in) {

            uint32_t m_pc = dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__exe_pc;

            if (m_pc == 0x62c) {
                assert((prevpc & 1) == 0);
                uint32_t callpos = ((prevpc & 0x3fffff) >> 1) + 1;
                uint32_t call = dut.rootp->emu__DOT__rom[callpos];
                printf("Syscall %x %x %s\n", prevpc, call, systemCallNameToString(static_cast<SystemCallType>(call)));
                leave_sys_callpc = prevpc + 4;
            }

            if (m_pc == leave_sys_callpc) {
                printf("Return from Syscall %x %x\n",
                       dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__flags,
                       dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__flagssr);
                printstate(dut);
            }

            prevpc = m_pc;
        }

        // Trace CPU state
        if (dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__decodeopc &&
            print_instructions && dut.rootp->emu__DOT__cditop__DOT__scc68070_0__DOT__clkena_in) {

            printstate(dut);
        }

        static int output_index = 0;
        static int frame_index = 0;

        // Simulate television
        if (dut.rootp->emu__DOT__cditop__DOT__mcd212_inst__DOT__new_frame) {
            char filename[100];

            if (frame_index == 283) {
                printf("Press a button!\n");
                dut.rootp->emu__DOT__JOY0 = 0b10000;
            }
            if (frame_index == 284) {
                printf("Release a button!\n");
                dut.rootp->emu__DOT__JOY0 = 0b00000;
            }

            if (output_index > 100) {
                auto current = std::chrono::system_clock::now();
                std::chrono::duration<double> elapsed_seconds = current - start;
                sprintf(filename, "video_%02d.png", frame_index);
                write_png_file(filename);
                printf("Written %s %d\n", filename, output_index);
                fprintf(stderr, "Written %s after %.2fs\n", filename, elapsed_seconds.count());
                frame_index++;
            }
            output_index = 0;
        }

        if (output_index < size - 6) {
            if (dut.VGA_DE) {
                output_image[output_index++] = dut.VGA_R;
                output_image[output_index++] = dut.VGA_G;
                output_image[output_index++] = dut.VGA_B;
            } else {
                output_image[output_index++] = do_trace ? 80 : 10;
                output_image[output_index++] = 10;
                output_image[output_index++] = 10;
            }
        }

        if (status == SIGINT)
            break;
    }
    fclose(f_cd_bin);

    if (1) {
        printf("Writing rampdump!\n");
        FILE *f = fopen("ramdump2.bin", "wb");
        assert(f);
        fwrite(&dut.rootp->emu__DOT__ram[0], 1, 1024 * 256 * 4, f);
        fclose(f);
    }
}

int main(int argc, char **argv) {
    // Initialize Verilators variables
    Verilated::commandArgs(argc, argv);

    if (do_trace)
        Verilated::traceEverOn(true);

    tracetype_t m_trace;
    Vemu dut;

    if (signal(SIGINT, catch_function) == SIG_ERR) {
        fputs("An error occurred while setting a signal handler.\n", stderr);
        return EXIT_FAILURE;
    }

    dut.trace(&m_trace, 5);

    if (do_trace)
        m_trace.open("/tmp/waveform.vcd");

    do_justwait(m_trace, dut);

    fprintf(stderr, "Closing...\n");
    fflush(stdout);

    return 0;
}
