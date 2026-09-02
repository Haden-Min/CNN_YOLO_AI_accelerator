# `top_single_conv_tile_axi` Activation + Requantization 통합 가이드

## 1. 문서 목적

이 문서는 `activation_requant_int8_stream`을 현재 28×28 tile convolution 경로에
통합하기 위해 `top_single_conv_tile_axi.v`에서 수정해야 하는 내용을 정리한다.

통합 후 최종 출력 경로는 다음과 같다.

```text
top_single_conv_tile
  → 입력 채널 하나의 INT32 convolution 결과
  → tile_psum_buffer
  → 모든 입력 채널과 bias가 합쳐진 최종 INT32 psum
  → activation_requant_int8_stream
  → signed INT8 결과
  → 32비트 AXI word 변환
  → axis_output_fifo
  → M_AXIS / DMA
```

핵심 원칙은 activation과 requantization을 반드시 모든 입력 채널의 누적이 끝난
뒤에 한 번만 적용하는 것이다.

## 2. 수정 대상과 수정하지 않을 대상

### 주요 수정 대상

- `rtl/pipeline_conv/top_single_conv_tile_axi.v`
  - AXI-Lite requant 파라미터 레지스터 추가
  - 실행용 파라미터 래치 추가
  - fused 모듈 인스턴스 추가
  - ready/valid/last 연결 변경
  - INT8 결과의 32비트 AXI word 변환
  - configuration 및 fused 상태 오류 처리

### 함께 수정해야 하는 파일

- `rtl/filelists/tile_conv_rtl.f`
  - `activation_requant_int8_stream.v` 추가
- tile AXI testbench와 multi-IC testbench
  - 기존 INT32 예상 결과를 fused INT8 기준 결과로 변경
- PS 제어 코드 또는 driver
  - 출력 채널 실행 전에 AXI-Lite requant 파라미터 설정
  - DMA 출력에서 각 32비트 word의 하위 8비트를 signed INT8로 해석
- AXI register map 관련 문서
  - 새 레지스터 주소와 설정 순서 반영

### 원칙적으로 수정하지 않는 파일

- `rtl/pipeline_conv/top_single_conv_tile.v`
- `rtl/pipeline_conv/conv_datapath.v`
- convolution 연산용 `tile_conv_controller.v`
- 기존 `activation.v`

`top_single_conv_tile`은 입력 채널 하나의 INT32 convolution 결과를 생성한다.
이 안에서 activation이나 requantization을 수행하면 채널마다 비선형 함수와
INT8 변환이 적용되어 올바른 다중 입력 채널 누적 결과를 얻을 수 없다.

```text
잘못된 순서:
requant(activation(conv(IC0))) + requant(activation(conv(IC1))) + ...

올바른 순서:
requant(activation(bias + conv(IC0) + conv(IC1) + ...))
```

## 3. 현재 경로와 변경할 경로

현재 `top_single_conv_tile_axi.v`의 출력 연결은 다음과 같다.

```text
tile_psum_buffer.result_data_o
  → axis_output_fifo.s_data_i

tile_psum_buffer.result_valid_o
  → axis_output_fifo.s_valid_i

axis_output_fifo.s_ready_o
  → tile_psum_buffer.result_ready_i
```

이를 다음과 같이 변경한다.

```text
tile_psum_buffer.result_data_o
  → fused.acc_i

tile_psum_buffer.result_valid_o
  → fused.valid_i

fused.ready_o
  → tile_psum_buffer.result_ready_i

fused.data_o
  → 32비트 AXI word 변환
  → axis_output_fifo.s_data_i

fused.valid_o
  → axis_output_fifo.s_valid_i

axis_output_fifo.s_ready_o
  → fused.ready_i
```

전체 backpressure 경로는 다음과 같다.

```text
M_AXIS TREADY
  → output FIFO
  → fused pipeline
  → tile_psum_buffer
  → tile core result interface
```

FIFO가 가득 차면 fused pipeline과 psum buffer가 함께 정지한다. fused 모듈은
stall 중 `data_o`, `last_o`, `tag_o`, `valid_o`를 유지하므로 별도 skid buffer를
추가할 필요가 없다.

## 4. Wrapper parameter 추가

기존 convolution의 `MUL_WIDTH`는 INT8×INT8 곱셈 결과 폭을 의미하므로 fused
requant multiplier 폭으로 재사용하지 않는다. 의미가 다른 parameter를 별도로
추가한다.

권장 parameter는 다음과 같다.

```verilog
parameter REQUANT_MULT_WIDTH  = 32,
parameter REQUANT_SHIFT_WIDTH = 6,
parameter ZERO_POINT_WIDTH    = 32
```

`REQUANT_SHIFT_WIDTH=6`이면 shift 값 0~63을 표현할 수 있다.

## 5. AXI-Lite register map 확장

현재 register map은 `0x24`까지 사용하고 있다. 기본 `AXI_ADDR_WIDTH=6`이면
`0x00`~`0x3C`를 접근할 수 있으므로 남은 여섯 word를 requant 설정에 사용할 수
있다.

| 주소 | 이름 | 사용 비트 | 의미 |
|---:|---|---|---|
| `0x28` | `ACTIVATION_MODE` | `[1:0]` | `00=LINEAR`, `01=LEAKY_RELU`, 나머지는 예약값 |
| `0x2C` | `MULTIPLIER_POS` | `[31:0]` | 양수 경로 signed multiplier |
| `0x30` | `SHIFT_POS` | `[5:0]` | 양수 경로 right shift |
| `0x34` | `MULTIPLIER_NEG` | `[31:0]` | Leaky 음수 경로 signed multiplier |
| `0x38` | `SHIFT_NEG` | `[5:0]` | Leaky 음수 경로 right shift |
| `0x3C` | `ZERO_POINT` | `[31:0]` | signed output zero point |

위 주소는 현재 주소 공간에 정확히 들어가지만 AXI/control 담당자와 최종 합의한
뒤 고정해야 한다.

RTL에는 다음 localparam을 추가한다.

```verilog
localparam REG_ACTIVATION_MODE = 4'd10;
localparam REG_MULTIPLIER_POS  = 4'd11;
localparam REG_SHIFT_POS       = 4'd12;
localparam REG_MULTIPLIER_NEG  = 4'd13;
localparam REG_SHIFT_NEG       = 4'd14;
localparam REG_ZERO_POINT      = 4'd15;
```

### AXI write 처리

각 주소의 `write_commit_w`와 `WSTRB`를 확인하여 shadow register를 갱신한다.
32비트 multiplier와 zero point는 byte strobe를 모두 반영하는 것이 원칙이다.
초기 구현에서 partial write를 지원하지 않는다면 `WSTRB=4'b1111`만 허용하고
그 외 write는 error로 기록한다.

### AXI readback 처리

기존 AXI read `case`에 여섯 레지스터를 추가한다. 작은 필드는 상위 비트를
0으로 채운다.

```verilog
REG_ACTIVATION_MODE: s_axi_rdata <= {30'd0, activation_mode_shadow_r};
REG_MULTIPLIER_POS:  s_axi_rdata <= multiplier_pos_shadow_r;
REG_SHIFT_POS:       s_axi_rdata <= {{26{1'b0}}, shift_pos_shadow_r};
REG_MULTIPLIER_NEG:  s_axi_rdata <= multiplier_neg_shadow_r;
REG_SHIFT_NEG:       s_axi_rdata <= {{26{1'b0}}, shift_neg_shadow_r};
REG_ZERO_POINT:      s_axi_rdata <= zero_point_shadow_r;
```

## 6. Shadow register와 실행용 register 분리

fused 모듈의 파라미터를 AXI-Lite register에 직접 연결하면 PS가 연산 도중 값을
변경했을 때 한 출력 채널 안에서 서로 다른 coefficient가 사용될 수 있다.
따라서 설정용 shadow register와 실행용 active register를 분리한다.

```text
PS AXI-Lite write
  → shadow register
  → 첫 번째 IC의 run 명령에서 한 번 래치
  → active register
  → 모든 IC 처리 동안 값 고정
  → fused 모듈
```

권장 register 구성은 다음과 같다.

```verilog
reg [1:0] activation_mode_shadow_r;
reg signed [REQUANT_MULT_WIDTH-1:0] multiplier_pos_shadow_r;
reg [REQUANT_SHIFT_WIDTH-1:0] shift_pos_shadow_r;
reg signed [REQUANT_MULT_WIDTH-1:0] multiplier_neg_shadow_r;
reg [REQUANT_SHIFT_WIDTH-1:0] shift_neg_shadow_r;
reg signed [ZERO_POINT_WIDTH-1:0] zero_point_shadow_r;

reg [1:0] activation_mode_active_r;
reg signed [REQUANT_MULT_WIDTH-1:0] multiplier_pos_active_r;
reg [REQUANT_SHIFT_WIDTH-1:0] shift_pos_active_r;
reg signed [REQUANT_MULT_WIDTH-1:0] multiplier_neg_active_r;
reg [REQUANT_SHIFT_WIDTH-1:0] shift_neg_active_r;
reg signed [ZERO_POINT_WIDTH-1:0] zero_point_active_r;
```

### 파라미터를 래치하는 시점

출력 채널의 첫 번째 입력 채널을 시작할 때만 shadow 값을 active register로
복사한다.

```verilog
if (ctrl_run_tile_w && (state_r == ST_IDLE) &&
    param_loaded_r && first_channel_w) begin
    activation_mode_active_r <= activation_mode_shadow_r;
    multiplier_pos_active_r  <= multiplier_pos_shadow_r;
    shift_pos_active_r       <= shift_pos_shadow_r;
    multiplier_neg_active_r  <= multiplier_neg_shadow_r;
    shift_neg_active_r       <= shift_neg_shadow_r;
    zero_point_active_r      <= zero_point_shadow_r;
end
```

두 번째 IC부터 마지막 IC까지는 active register를 다시 쓰지 않는다. 이렇게 해야
하나의 출력 채널을 계산하는 동안 requant 파라미터가 고정된다.

### 설정 write 허용 시점

권장 규칙은 다음과 같다.

- `state_r == ST_IDLE`이고 `current_ic_r == 0`일 때만 shadow register write 허용
- 첫 IC 실행이 시작된 뒤 마지막 IC 출력이 끝날 때까지 변경 금지
- 금지된 시점의 write는 값을 무시하고 error flag 설정

현재 설계는 IC 사이에도 `ST_IDLE`로 돌아오므로 `ST_IDLE`만 검사해서는 부족하다.
반드시 `current_ic_r == 0` 조건도 함께 검사해야 한다.

## 7. Configuration valid 관리

설정되지 않은 multiplier를 사용해 출력을 모두 0으로 만드는 문제를 방지하기
위해 configuration valid를 관리한다.

권장 구현은 여섯 register의 write 여부를 추적하는 것이다.

```verilog
reg [5:0] requant_write_seen_r;
wire requant_config_valid_w = &requant_write_seen_r;
```

각 설정 register가 정상적으로 쓰이면 대응 bit를 1로 만든다. 다음 상황에서는
write-seen 값을 지운다.

- hardware reset
- soft reset
- 새 출력 채널 설정을 시작하는 `TOTAL_IC` write
- 마지막 결과의 AXI `TLAST`가 전송되어 현재 출력 채널이 종료된 시점

소프트웨어 순서는 `TOTAL_IC` 설정 후 requant register 여섯 개를 쓰는 것으로
고정한다.

첫 IC에 대한 `run` 명령에서 configuration이 유효하지 않으면 core를 시작하지
않고 error와 `done_sticky_r`를 설정한다. 중간 IC에서는 이미 래치된 active
configuration을 계속 사용한다.

## 8. 새 signal 선언

psum 주소를 더 이상 버리지 않고 fused tag로 전달한다.

```verilog
wire [OUTPUT_ADDR_WIDTH-1:0] psum_result_addr_w;

wire fused_ready_w;
wire signed [7:0] fused_data_w;
wire fused_clipped_w;
wire fused_mode_error_w;
wire [OUTPUT_ADDR_WIDTH-1:0] fused_tag_w;
wire fused_last_w;
wire fused_valid_w;
wire fifo_input_ready_w;
wire [AXI_DATA_WIDTH-1:0] fused_axis_word_w;
```

`tile_psum_buffer`의 현재 미사용 주소 출력을 연결한다.

```verilog
.result_addr_o(psum_result_addr_w)
```

## 9. Fused 모듈 인스턴스 추가

권장 인스턴스 형태는 다음과 같다.

```verilog
activation_requant_int8_stream #(
    .ACC_WIDTH(ACC_WIDTH),
    .MULT_WIDTH(REQUANT_MULT_WIDTH),
    .SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
    .ZERO_POINT_WIDTH(ZERO_POINT_WIDTH),
    .TAG_WIDTH(OUTPUT_ADDR_WIDTH)
) u_activation_requant (
    .clk(aclk),
    .rst_n(core_resetn_w),
    .acc_i(psum_result_data_w),
    .activation_mode_i(activation_mode_active_r),
    .multiplier_pos_i(multiplier_pos_active_r),
    .shift_pos_i(shift_pos_active_r),
    .multiplier_neg_i(multiplier_neg_active_r),
    .shift_neg_i(shift_neg_active_r),
    .zero_point_i(zero_point_active_r),
    .tag_i(psum_result_addr_w),
    .last_i(psum_result_last_w),
    .valid_i(psum_result_valid_w),
    .ready_o(psum_result_ready_w),
    .data_o(fused_data_w),
    .clipped_o(fused_clipped_w),
    .mode_error_o(fused_mode_error_w),
    .tag_o(fused_tag_w),
    .last_o(fused_last_w),
    .valid_o(fused_valid_w),
    .ready_i(fifo_input_ready_w)
);
```

`rst_n`에는 `core_resetn_w`를 연결하여 hardware reset과 wrapper soft reset 모두에서
pipeline의 valid bit가 지워지도록 한다. 정상 완료된 transaction 뒤에는 fused
pipeline이 비어 있으므로 매 tile run마다 별도 reset을 걸 필요는 없다.

## 10. FIFO 입력 변경과 INT8 word 포맷

초기 통합에서는 INT8 네 개를 한 word에 packing하지 않고 결과 하나당 AXI
32비트 word 하나를 유지한다.

```text
TDATA[7:0]  = signed INT8의 2의 보수 bit pattern
TDATA[31:8] = 0
```

```verilog
assign fused_axis_word_w =
    {{(AXI_DATA_WIDTH-8){1'b0}}, fused_data_w};
```

FIFO 입력은 다음과 같이 변경한다.

```verilog
.s_data_i(fused_axis_word_w),
.s_last_i(fused_last_w),
.s_valid_i(fused_valid_w),
.s_ready_o(fifo_input_ready_w)
```

상위 비트는 sign extension하지 않고 0으로 채운다. 음수 여부는 하위 8비트를
signed INT8로 해석하여 판단한다.

결과 하나당 한 word 정책을 유지하므로 다음 값은 바뀌지 않는다.

- 출력 word 수: `OUTPUT_SIZE`, 28×28 tile에서는 676
- `stream_out_count_r`의 증가 조건
- DMA 수신 길이: `OUTPUT_SIZE × 4 byte`
- `TLAST` 위치: 676번째 word

향후 INT8 네 개를 한 word에 packing하려면 별도의 packer, output count,
`TLAST`, DMA 길이 변경이 필요하므로 이번 통합 범위에는 포함하지 않는다.

## 11. FSM 변경 여부

### 새로운 상태는 추가하지 않는다

fused pipeline의 no-stall latency가 6 cycle 추가되지만 기존 FSM은 마지막 core
계산이 끝난 직후 transaction 완료를 선언하지 않는다.

```text
ST_TILE_RUN
  → core_done_w && last_channel_w
  → ST_TILE_DRAIN
  → fused pipeline과 FIFO에 남은 데이터 배출
  → M_AXIS에서 valid && ready && last
  → ST_IDLE
```

따라서 `ST_FUSED_WAIT` 같은 새 상태는 필요하지 않다. 기존 `ST_TILE_DRAIN`이
fused pipeline drain 시간까지 포함한다.

### 기존 완료 조건 유지

transaction 완료는 기존과 동일하게 다음 handshake에서만 발생해야 한다.

```verilog
m_axis_tvalid && m_axis_tready && m_axis_tlast
```

`core_done_w`, `psum_result_last_w`, `fused_last_w`만으로 `done_sticky_r`를
설정하면 안 된다. 이 시점에는 DMA가 마지막 데이터를 아직 받지 않았을 수 있다.

### `run` 조건 보강

`ST_IDLE`에서 첫 IC를 시작할 때 기존 `param_loaded_r` 검사에 requant
configuration 검사를 추가한다.

```text
첫 IC:
  weight/bias parameter loaded
  AND requant configuration valid
  → start 허용 및 active parameter 래치

중간 IC:
  해당 IC의 weight parameter loaded
  AND 이전에 래치한 active configuration valid
  → start 허용
```

즉 FSM state 개수는 유지하지만 `ST_IDLE`의 start guard와 첫 IC 시작 시 수행하는
register 동작은 수정한다.

## 12. Error 및 상태 처리

기존 `error_flags_r`의 미사용 비트에 다음 오류를 배정하는 것을 권장한다. 실제
bit 번호는 AXI/control 담당자와 합의한다.

| 권장 항목 | 발생 조건 |
|---|---|
| `REQUANT_CONFIG_MISSING` | 첫 IC run 시 여섯 설정값이 모두 준비되지 않음 |
| `REQUANT_WRITE_LOCKED` | 첫 IC 시작 이후 마지막 IC 완료 전에 설정 register write 시도 |
| `REQUANT_MODE_ERROR` | fused 결과가 예약된 activation mode를 사용함 |
| `REQUANT_CLIPPED` | 적어도 한 결과가 -128 또는 127로 saturation됨 |

`mode_error`와 `clipped`는 fused 출력 transaction이 실제 FIFO로 전달될 때
기록한다.

```verilog
if (fused_valid_w && fifo_input_ready_w) begin
    if (fused_mode_error_w)
        error_flags_r[REQUANT_MODE_ERROR_BIT] <= 1'b1;
    if (fused_clipped_w)
        clipped_sticky_r <= 1'b1;
end
```

Saturation은 정상적인 quantization에서도 발생할 수 있으므로 fatal error로
취급하기보다는 별도 sticky status 또는 counter로 관리하는 것이 적절하다.
예약 activation mode는 configuration 오류이므로 error flag로 처리한다.

## 13. Reset과 transaction 경계

### Hardware reset과 soft reset

다음 값들을 초기화한다.

- shadow/active requant register
- `requant_write_seen_r`
- active configuration valid
- mode-error sticky 상태
- clipping sticky 상태 또는 counter
- fused pipeline valid 상태

fused 모듈의 `rst_n`을 `core_resetn_w`에 연결하면 기존 soft reset으로 pipeline을
비울 수 있다.

### IC 사이의 경계

마지막 IC가 아닌 경우 `tile_psum_buffer`는 결과를 외부로 출력하지 않고 BRAM에만
저장한다. 따라서 fused 모듈에는 valid transaction이 들어가지 않는다. IC가
바뀔 때 fused pipeline을 reset하지 않는다.

### 출력 채널 종료

마지막 `M_AXIS TLAST` handshake에서 다음 작업을 수행한다.

- 기존처럼 `current_ic_r`를 0으로 복귀
- 현재 출력 채널 완료 처리
- 다음 출력 채널이 새 requant 설정을 쓰도록 configuration valid 또는
  write-seen 상태 초기화

정상 경로에서는 마지막 AXI word가 전송된 시점에 fused pipeline과 FIFO에 현재
transaction 데이터가 남아 있지 않다.

## 14. 기존 count 및 status에 미치는 영향

### 변경하지 않아도 되는 항목

- `stream_in_count_r`
- `stream_out_count_r`
- `REG_TILE_INPUTS`
- `REG_TILE_OUTPUTS`
- `PARAM_WORDS=10`
- 기존 weight 9개 + bias 1개 parameter packet
- `TOTAL_IC`, `CURRENT_IC` 의미

Requant 파라미터는 AXI-Lite로 받으므로 기존 10-word parameter packet은 변경하지
않는다.

### 확인할 항목

현재 `outputting_w`는 FIFO level 또는 `ST_TILE_DRAIN`으로 계산한다.
`ST_TILE_DRAIN`이 fused pipeline의 대기 시간도 포함하므로 완료 제어에는 문제가
없다. 다만 status bit를 “FIFO 또는 fused 내부에 출력 데이터가 존재함”이라는
정확한 의미로 사용하려면 fused pipeline occupancy를 별도로 추적해야 한다.
이번 통합에서 status의 의미를 단순히 “출력 transaction 진행 중”으로 유지하면
추가 occupancy counter는 필요하지 않다.

## 15. 소프트웨어 실행 순서

출력 채널 하나에 대한 권장 제어 순서는 다음과 같다.

```text
1. accelerator가 IDLE인지 확인
2. TOTAL_IC 설정
3. ACTIVATION_MODE 설정
4. MULTIPLIER_POS 설정
5. SHIFT_POS 설정
6. MULTIPLIER_NEG 설정
7. SHIFT_NEG 설정
8. ZERO_POINT 설정

각 IC에 대해 반복:
9.  해당 IC의 weight 9개 + bias word parameter packet 전송
10. tile run 명령
11. 마지막 IC가 아니면 channel done 확인 후 다음 IC 진행

마지막 IC:
12. S2MM DMA로 OUTPUT_SIZE개의 32비트 word 수신
13. TLAST 및 done 확인
14. 각 word의 하위 8비트를 signed INT8로 해석
```

bias packet은 기존 형식을 유지한다. `tile_psum_buffer`가 첫 IC에서만
`layer_bias_r`를 더하므로 bias를 입력 채널마다 중복 적용하지 않는다.

## 16. Filelist 변경

`rtl/filelists/tile_conv_rtl.f`에서 `top_single_conv_tile_axi.v`보다 앞에 다음
파일을 추가한다.

```text
rtl/pipeline_conv/activation_requant_int8_stream.v
```

Vivado는 Verilog source 순서에 영향을 받을 수 있으므로 인스턴스하는 top보다
앞에 두는 것이 안전하다.

## 17. Testbench 필수 검증 항목

### AXI-Lite register 검증

- 여섯 requant register write/readback
- signed multiplier와 zero point bit pattern 유지
- shift의 하위 6비트 처리
- 첫 IC run 시 active register 래치
- 중간 IC에서 설정값 변경 시도 차단
- configuration 미설정 상태에서 run 거부
- soft reset 후 configuration valid 초기화

### 계산 검증

- `LINEAR`, 양수/음수/0
- `LEAKY_RELU`, 양수/음수/0
- 양수/음수 각각 독립 multiplier와 shift 사용
- 양수 saturation 127
- 음수 saturation -128
- zero point 적용
- 반올림 경계값
- 예약 activation mode의 LINEAR 계산과 mode error

### Multi-IC 검증

- 마지막 IC 전에는 fused/FIFO/M_AXIS 출력이 없음
- 모든 IC의 psum과 bias를 합친 뒤 activation이 한 번만 적용됨
- 첫 IC에서 래치한 coefficient가 마지막 IC까지 유지됨
- 마지막 IC 결과가 정확히 `OUTPUT_SIZE`개 출력됨
- 마지막 결과에만 `TLAST`가 붙음

### Backpressure 검증

- `M_AXIS TREADY=0`에서 data/valid/last 안정성
- FIFO full 시 fused pipeline stall
- fused stall 시 psum buffer와 core까지 ready가 전달됨
- stall 해제 후 결과 누락, 중복, 순서 변경이 없음
- 마지막 결과가 실제 AXI handshake되기 전에는 done이 발생하지 않음

### 출력 포맷 검증

- `TDATA[7:0]`이 signed INT8 결과와 일치
- `TDATA[31:8]`이 항상 0
- 출력 word 수가 기존과 동일하게 `OUTPUT_SIZE`

## 18. 합성 및 timing 확인

standalone fused 모듈의 out-of-context timing 통과만으로 전체 시스템 timing을
보장할 수 없다. 통합 후 다음을 다시 확인한다.

- synthesis top: `top_single_conv_tile_axi`
- target: `XC7Z020CLG400-1`
- 목표 clock: 10 ns
- WNS/TNS
- DSP48E1, LUT, register, BRAM 사용량
- psum → fused multiplier 입력 경로
- fused → FIFO 입력 경로
- 전역 backpressure ready 경로

특히 ready 신호가 core까지 조합 경로로 길어지는지 확인해야 한다. timing이
나빠지면 ready 경로에 별도 elastic buffer를 추가하는 방안을 검토하지만, 최초
통합 단계에서 미리 추가할 필요는 없다.

## 19. 구현 순서 체크리스트

- [ ] requant 관련 wrapper parameter 추가
- [ ] AXI-Lite register 주소 localparam 추가
- [ ] shadow/active register 선언
- [ ] configuration write-seen 또는 valid 관리 추가
- [ ] AXI write decode와 write 제한 추가
- [ ] AXI readback case 추가
- [ ] 첫 IC run 시 active parameter 래치
- [ ] configuration 누락 시 run 차단
- [ ] `tile_psum_buffer.result_addr_o` 연결
- [ ] fused용 ready/valid/data/tag/last/status signal 선언
- [ ] `activation_requant_int8_stream` 인스턴스 추가
- [ ] psum → fused → FIFO backpressure 연결
- [ ] fused INT8 결과를 32비트 zero-extended AXI word로 변환
- [ ] FIFO 입력을 psum 직결에서 fused 출력으로 변경
- [ ] mode error와 clipping 상태 처리
- [ ] reset 및 soft-reset 초기화 추가
- [ ] 마지막 TLAST에서 다음 출력 채널용 config 상태 초기화
- [ ] `tile_conv_rtl.f`에 fused 파일 추가
- [ ] AXI 및 multi-IC testbench 예상 결과 변경
- [ ] random downstream stall regression 실행
- [ ] full top synthesis/implementation timing 재확인

## 20. 최종 결론

통합의 중심 수정 파일은 `top_single_conv_tile_axi.v`이다.
`top_single_conv_tile`과 convolution FSM은 수정하지 않는다. wrapper FSM도 새로운
상태를 추가하지 않고 기존 `ST_TILE_DRAIN`을 그대로 사용한다.

하지만 단순히 fused 모듈 하나를 인스턴스하는 것으로 끝나지는 않는다. 다음 네
부분을 하나의 변경으로 처리해야 한다.

1. 출력 채널별 requant 파라미터를 받는 AXI-Lite register와 안전한 래치
2. psum → fused → FIFO의 ready/valid/last backpressure 연결
3. signed INT8 결과의 32비트 AXI word 변환
4. configuration, mode error, saturation, reset 및 완료 조건 검증

이 구성을 따르면 여러 입력 채널을 INT32로 모두 누적한 뒤에만 activation과
requantization이 적용되며, fused pipeline latency와 DMA backpressure도 기존
transaction 완료 구조 안에서 안전하게 처리할 수 있다.
