# Serial Input-Channel Accumulation

## 구현 범위

현재 tile datapath의 병렬도는 `IC_PAR=1`이다. 3x3 공간 tap 9개는 병렬로
계산하지만 입력 채널은 한 번에 하나씩 처리한다. 네트워크의 전체 입력 채널 수는
AXI-Lite `TOTAL_IC` 레지스터로 지정하며 최대값은 기본 1024이다.

```text
S_AXIS -> 3x3 tile core -> tile_psum_buffer -> output FIFO -> M_AXIS
                              |       |
                              + BRAM  + 32-bit add
```

`tile_psum_buffer`는 출력 위치별 INT32 partial sum을 저장한다.

```text
IC=0: psum[address] = bias + channel_conv
middle IC: psum[address] = psum[address] + channel_conv
last IC: final = psum[address] + channel_conv -> output FIFO
```

첫 채널이 모든 주소를 덮어쓰므로 BRAM 전체를 초기화할 필요가 없다. 중간 채널의
결과는 AXI 출력으로 보내지 않으며 마지막 채널의 완료 결과만 PS로 전송한다.

## PS 실행 순서

한 출력 채널에 대해 다음 순서를 사용한다.

1. idle 상태에서 `TOTAL_IC`에 실제 입력 채널 수를 쓴다.
2. 각 입력 채널마다 10-word parameter packet을 보낸다.
3. parameter packet은 INT8 weight 9개와 INT32 bias 1개이다.
4. 첫 입력 채널의 bias만 layer bias로 저장된다. 이후 bias word는 packet 크기를
   고정하기 위해 존재하며 누적값에 다시 더하지 않는다.
5. `RUN_TILE`을 실행하고 해당 채널의 CHW tile 하나를 보낸다.
6. 중간 채널에서는 IRQ를 기다린 뒤 `CURRENT_IC` 증가를 확인하고 다음 채널로 간다.
7. 마지막 채널에서만 S2MM buffer를 준비하며 완료 결과 한 타일을 받는다.

동일한 MM2S DMA 채널을 parameter packet과 tile packet에 순차적으로 재사용한다.

## 추가 AXI-Lite 레지스터

| Offset | 이름 | 동작 |
| --- | --- | --- |
| `0x20` | `TOTAL_IC` | 1~1024, idle 상태에서만 쓰기 가능 |
| `0x24` | `CURRENT_IC` | 현재 0-based 입력 채널 index |

`TOTAL_IC=0` 또는 최대값보다 큰 값을 쓰면 `ERROR[6]`이 설정된다. 중간 채널이
완료되면 `STATUS.done`과 IRQ가 설정되고 wrapper는 idle로 돌아가지만 AXI 출력은
발생하지 않는다.

## RTL 구성

- `top_single_conv_tile`: 한 입력 채널의 bias 없는 3x3 convolution을 실행한다.
- `tile_psum_buffer`: synchronous BRAM read, INT32 add, final-channel output handshake를
  처리한다.
- `top_single_conv_tile_axi`: `TOTAL_IC`, `CURRENT_IC`, parameter/tile command 순서를
  관리한다.
- `axis_output_fifo`: 마지막 채널 결과와 DMA backpressure를 분리한다.

## 검증 결과

Vivado Simulator 2024.1:

```text
PASS: tb_multi_ic_conv_tile_axi channels=3 tile=6x6 outputs=16 status=0x00000811
PASS: tb_single_conv_tile_axi tile=28x28 inputs=784 outputs=676 status=0x00000811
PASS: tb_single_conv_tile_axi tile=16x16 inputs=256 outputs=196 status=0x00000811
```

XC7Z020CLG400-1, 100 MHz, OOC place/route:

```text
WNS                 = +1.234 ns
TNS                 =  0.000 ns
Setup failing paths =  0
Total LUT           = 1143
Total FF            = 838
Partial-sum memory  = 1 RAMB36
```

OOC timing은 AXI DMA/interconnect가 포함되지 않은 결과이므로 block design 전체
implementation에서 다시 확인해야 한다.

## 재현 명령

저장소 루트에서 실행한다.

```powershell
& "C:\Xilinx\Vivado\2024.1\bin\xvlog.bat" -f rtl/filelists/tile_conv_multi_ic_axi_tb.f
& "C:\Xilinx\Vivado\2024.1\bin\xelab.bat" tb_multi_ic_conv_tile_axi -s tb_multi_ic_conv_tile_axi_sim
& "C:\Xilinx\Vivado\2024.1\bin\xsim.bat" tb_multi_ic_conv_tile_axi_sim -runall

python sw/golden/script/generate_single_conv_fixture.py --fixture multi_ic_conv_tile_28
python sw/golden/model/conv2d_int8_reference.py --fixture sw/fixture/multi_ic_conv_tile_28 --check-only
```
