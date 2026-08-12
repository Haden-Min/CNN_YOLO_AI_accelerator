`timescale 1ns/1ps

module tb_tile_window_path;
    localparam DATA_WIDTH = 8;
    localparam TILE_WIDTH = 28;
    localparam COL_WIDTH = $clog2(TILE_WIDTH);

    reg clk;
    reg rst_n;

    reg write_en_i;
    reg [1:0] write_bank_i;
    reg [COL_WIDTH-1:0] write_col_i;
    reg signed [DATA_WIDTH-1:0] write_data_i;

    reg read_en_i;
    reg [1:0] top_bank_i;
    reg [COL_WIDTH-1:0] read_col_i;
    wire signed [3*DATA_WIDTH-1:0] column_o;
    wire column_valid_o;

    reg start_row_i;
    wire column_ready_o;
    wire signed [9*DATA_WIDTH-1:0] window_o;
    wire [COL_WIDTH-1:0] window_col_o;
    wire window_last_o;
    wire window_valid_o;
    reg window_ready_i;

    integer mismatch_count;
    integer checked_windows;

    tile_line_buffer_3row #(
        .DATA_WIDTH(DATA_WIDTH),
        .TILE_WIDTH(TILE_WIDTH),
        .COL_WIDTH(COL_WIDTH)
    ) u_line_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .write_en_i(write_en_i),
        .write_bank_i(write_bank_i),
        .write_col_i(write_col_i),
        .write_data_i(write_data_i),
        .read_en_i(read_en_i),
        .top_bank_i(top_bank_i),
        .read_col_i(read_col_i),
        .column_o(column_o),
        .column_valid_o(column_valid_o)
    );

    tile_window_generator_3x3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .TILE_WIDTH(TILE_WIDTH),
        .COL_WIDTH(COL_WIDTH)
    ) u_window_generator (
        .clk(clk),
        .rst_n(rst_n),
        .start_row_i(start_row_i),
        .column_i(column_o),
        .column_valid_i(column_valid_o),
        .column_ready_o(column_ready_o),
        .window_o(window_o),
        .window_col_o(window_col_o),
        .window_last_o(window_last_o),
        .window_valid_o(window_valid_o),
        .window_ready_i(window_ready_i)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function signed [DATA_WIDTH-1:0] pixel_value;
        input integer row;
        input integer col;
        integer value;
        begin
            value = ((row * 37 + col * 7 + 11) % 101) - 50;
            pixel_value = value;
        end
    endfunction

    task write_row;
        input [1:0] bank;
        input integer image_row;
        integer col;
        begin
            for (col = 0; col < TILE_WIDTH; col = col + 1) begin
                @(negedge clk);
                write_en_i = 1'b1;
                write_bank_i = bank;
                write_col_i = col[COL_WIDTH-1:0];
                write_data_i = pixel_value(image_row, col);
            end
            @(negedge clk);
            write_en_i = 1'b0;
        end
    endtask

    task check_window;
        input integer image_row;
        input integer output_col;
        integer ky;
        integer kx;
        reg signed [DATA_WIDTH-1:0] got;
        reg signed [DATA_WIDTH-1:0] expected;
        begin
            if (!window_valid_o) begin
                $display("FAIL: missing window row=%0d col=%0d", image_row, output_col);
                mismatch_count = mismatch_count + 1;
            end

            if (window_col_o !== output_col[COL_WIDTH-1:0]) begin
                $display("FAIL: window column row=%0d got=%0d expected=%0d",
                         image_row, window_col_o, output_col);
                mismatch_count = mismatch_count + 1;
            end

            if (window_last_o !== (output_col == TILE_WIDTH - 3)) begin
                $display("FAIL: window last row=%0d col=%0d got=%0b",
                         image_row, output_col, window_last_o);
                mismatch_count = mismatch_count + 1;
            end

            for (ky = 0; ky < 3; ky = ky + 1) begin
                for (kx = 0; kx < 3; kx = kx + 1) begin
                    got = window_o[(ky*3+kx)*DATA_WIDTH +: DATA_WIDTH];
                    expected = pixel_value(image_row + ky, output_col + kx);
                    if (got !== expected) begin
                        $display("FAIL: pixel row=%0d col=%0d ky=%0d kx=%0d got=%0d expected=%0d",
                                 image_row, output_col, ky, kx, got, expected);
                        mismatch_count = mismatch_count + 1;
                    end
                end
            end

            checked_windows = checked_windows + 1;
        end
    endtask

    task check_output_row;
        input [1:0] top_bank;
        input integer image_row;
        integer read_col;
        integer wait_cycles;
        reg signed [9*DATA_WIDTH-1:0] held_window;
        begin
            @(negedge clk);
            top_bank_i = top_bank;
            start_row_i = 1'b1;
            @(negedge clk);
            start_row_i = 1'b0;

            for (read_col = 0; read_col < TILE_WIDTH; read_col = read_col + 1) begin
                if (!column_ready_o) begin
                    $display("FAIL: column path not ready before read row=%0d col=%0d",
                             image_row, read_col);
                    mismatch_count = mismatch_count + 1;
                end

                read_en_i = 1'b1;
                read_col_i = read_col[COL_WIDTH-1:0];
                @(negedge clk);
                read_en_i = 1'b0;

                wait_cycles = 0;
                while (!column_valid_o && wait_cycles < 8) begin
                    @(negedge clk);
                    wait_cycles = wait_cycles + 1;
                end
                if (!column_valid_o) begin
                    $display("FAIL: column timeout row=%0d col=%0d", image_row, read_col);
                    $finish;
                end

                @(negedge clk);

                if (read_col >= 2) begin
                    check_window(image_row, read_col - 2);

                    if ((read_col % 5) == 2) begin
                        held_window = window_o;
                        repeat (2) begin
                            @(negedge clk);
                            if (!window_valid_o || window_o !== held_window) begin
                                $display("FAIL: window changed under backpressure row=%0d col=%0d",
                                         image_row, read_col - 2);
                                mismatch_count = mismatch_count + 1;
                            end
                        end
                    end

                    window_ready_i = 1'b1;
                    @(negedge clk);
                    window_ready_i = 1'b0;
                end
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        write_en_i = 1'b0;
        write_bank_i = 2'd0;
        write_col_i = {COL_WIDTH{1'b0}};
        write_data_i = {DATA_WIDTH{1'b0}};
        read_en_i = 1'b0;
        top_bank_i = 2'd0;
        read_col_i = {COL_WIDTH{1'b0}};
        start_row_i = 1'b0;
        window_ready_i = 1'b0;
        mismatch_count = 0;
        checked_windows = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        write_row(2'd0, 0);
        write_row(2'd1, 1);
        write_row(2'd2, 2);
        check_output_row(2'd0, 0);

        write_row(2'd0, 3);
        check_output_row(2'd1, 1);

        write_row(2'd1, 4);
        check_output_row(2'd2, 2);

        write_row(2'd2, 5);
        check_output_row(2'd0, 3);

        if (checked_windows != 4 * (TILE_WIDTH - 2)) begin
            $display("FAIL: checked windows=%0d expected=%0d",
                     checked_windows, 4 * (TILE_WIDTH - 2));
            $finish;
        end
        if (mismatch_count != 0) begin
            $display("FAIL: mismatches=%0d", mismatch_count);
            $finish;
        end

        $display("PASS: tb_tile_window_path rows=4 windows=%0d", checked_windows);
        $finish;
    end
endmodule
