`timescale 1ns/1ps
`define headerSize 54  // 표준 BMP 헤더 크기
`define width 416
`define height 416
`define imageSize `width*`height*3  // 각 픽셀은 3바이트(R, G, B)

module tb_top();

    reg clk;
    reg reset;
    reg [7:0] imgDataR, imgDataG, imgDataB;
    integer file, file1, file2, i, j;
    reg imgDataValid;
    integer sentSize;
    integer rowSize, paddingSize;
    reg [7:0] paddingByte;
    reg [7:0] imgDataArray[0:`height-1][0:`width-1][0:2];  // [행][열][색상]


    reg padding_en;

    wire [3343:0] R_row0;
    wire [3343:0] G_row0;
    wire [3343:0] B_row0;
    wire [3343:0] R_row1;
    wire [3343:0] G_row1;
    wire [3343:0] B_row1;
    wire [3343:0] R_row2;
    wire [3343:0] G_row2;
    wire [3343:0] B_row2;
    
    wire intr;

    padding padding(
                    .clk(clk),
                    .reset(reset),
                    .padding_en(padding_en),
                    .imgDataValid(imgDataValid),

                    .R_input(imgDataR),
                    .G_input(imgDataG),
                    .B_input(imgDataB),

                    .intr(intr),

                    .R_row0(R_row0), //418x8=3344
                    .G_row0(G_row0),
                    .B_row0(B_row0),

                    .R_row1(R_row1), //418x8=3344
                    .G_row1(G_row1),
                    .B_row1(B_row1),

                    .R_row2(R_row2), //418x8=3344
                    .G_row2(G_row2),
                    .B_row2(B_row2)

    );

   

    initial begin
        clk = 1'b0;
        forever begin
            #5 clk = ~clk;
        end
    end

    initial begin
        reset = 1;
        sentSize = 0;
        imgDataValid = 0;
        rowSize = `width * 3;
        paddingSize = (4 - (rowSize % 4)) % 4;
        padding_en = 0;
        #100;
        reset = 0;
        padding_en = 1;
        #100;
        file = $fopen("D:/Han/Verilog_codes/top/dog.bmp", "rb");  // 파일명에 맞게 수정
        file1 = $fopen("lined_image_416x416_rgb.bmp", "wb");
        file2 = $fopen("imageData.h", "w");

        if (file == 0 || file1 == 0 || file2 == 0) begin
            $display("파일을 열지 못했습니다.");
            $stop;
        end

        // 헤더 읽기 및 복사
        for(i = 0; i < `headerSize; i = i + 1) begin
            $fscanf(file, "%c", imgDataR);  // 헤더 바이트 읽기
            $fwrite(file1, "%c", imgDataR); // 헤더 바이트를 출력 파일에 쓰기
        end

        // 픽셀 데이터를 배열에 저장
        for(i = 0; i < `height; i = i + 1) begin
            // 한 행의 픽셀 읽기
            for(j = 0; j < `width; j = j + 1) begin
                $fscanf(file, "%c%c%c", imgDataArray[i][j][0], imgDataArray[i][j][1], imgDataArray[i][j][2]);  // B, G, R 순서
            end
            // 패딩 바이트 읽기
            for(j = 0; j < paddingSize; j = j + 1) begin
                $fscanf(file, "%c", paddingByte);
            end
        end

        // 파일 닫기
        $fclose(file);

        // 상단 행부터 픽셀 데이터를 처리
        for(i = 0; i < `height; i = i + 1) begin
            for(j = 0; j < `width; j = j + 1) begin
                @(posedge clk);
                imgDataB = imgDataArray[`height - 1 - i][j][0];
                imgDataG = imgDataArray[`height - 1 - i][j][1];
                imgDataR = imgDataArray[`height - 1 - i][j][2];
                $fwrite(file2, "%0d,%0d,%0d,", imgDataR, imgDataG, imgDataB);
                imgDataValid = 1'b1;
                // 필요한 경우 픽셀 데이터를 처리하거나 저장
            end
            @(posedge clk);
            imgDataValid = 1'b0;
        end

        $fclose(file2);
    end

    // always @(posedge clk) begin
    //     if(outDataValid) begin
    //         $fwrite(file1, "%c", outData);
    //         receivedData = receivedData + 1;
    //     end
    //     if(receivedData == `imageSize) begin
    //         $fclose(file1);
    //         $stop;
    //     end
    // end

    // top dut(
    //     // our module
    // );

endmodule