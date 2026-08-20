# PYNQ-Z2 28×28 Tile Accelerator Block Design Handoff

> **정식 재현 경로:** 현재 Block Design과 bitstream 생성은 자동화되어 있다.
> 팀원은 먼저 [`pynq-z2-reproduction-guide.md`](pynq-z2-reproduction-guide.md)의
> 스크립트 기반 절차를 사용한다. 아래 내용은 GUI에서 연결을 이해하거나 수동으로
> 점검할 때 쓰는 참고 문서다.

## 1. 목적과 검증 상태

이 문서는 보드를 가진 담당자가 현재 RTL을 Vivado 2024.1에서 PYNQ-Z2의 PS,
AXI DMA, DDR에 연결하고 최초 실기 동작을 재현하기 위한 작업 지시서이다.

패키징 top은 `cnn_tile_accel_ip`이며 내부 보드용 top은
`top_single_conv_tile_axi`이다. 이전 5×5/416×416 실험 top인
`top_single_conv_pipeline_axi`와 혼동하지 않는다.

현재 구현 범위:

- `28×28×IC` signed INT8 입력 타일, IC=1~1024 순차 처리
- 입력 채널별 `3×3` signed INT8 weight와 계층 INT32 bias 하나
- padding 없는 valid convolution
- `26×26×1 = 676`개의 signed INT32 출력
- AXI4-Lite 제어, AXI4-Stream 입출력

Vivado Simulator의 하위 모듈, 코어, AXI IC=1, AXI IC=3 누적 테스트가 모두
통과했다. PS/DMA/SmartConnect/가속기를 포함한 XC7Z020-1 전체 구현은 100 MHz에서
`WNS +0.946 ns`, `WHS +0.019 ns`, `TNS 0`, failing endpoint 0으로 통과했다.

## 2. 고정 환경

| 항목 | 값 |
| --- | --- |
| 보드 | TUL PYNQ-Z2 |
| FPGA | `xc7z020clg400-1` |
| Vivado | 2024.1 |
| 권장 PYNQ image | 3.1.1 |
| PL clock | 100 MHz, 단일 clock domain |
| RTL top | `top_single_conv_tile_axi` |
| AXIS width | 32 bit |
| AXI-Lite data/address width | 32 bit / 6 bit |

PYNQ-Z2 board preset이 Vivado에 보이지 않으면 TUL board file을 설치하고 Vivado를
재시작한 뒤 작업한다. DDR/MIO를 수동 추측해서 연결하지 않는다.

## 3. 작업 전 RTL 재검증

저장소 root에서 다음 세 테스트를 실행한다.

```powershell
C:\Xilinx\Vivado\2024.1\bin\xvlog.bat -f rtl/filelists/current/tile_window_tb.f
C:\Xilinx\Vivado\2024.1\bin\xelab.bat tb_tile_window_path -s tb_tile_window_path_sim
C:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_tile_window_path_sim -runall

C:\Xilinx\Vivado\2024.1\bin\xvlog.bat -f rtl/filelists/current/tile_conv_tb.f
C:\Xilinx\Vivado\2024.1\bin\xelab.bat tb_single_conv_tile -s tb_single_conv_tile_sim
C:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_single_conv_tile_sim -runall

C:\Xilinx\Vivado\2024.1\bin\xvlog.bat -f rtl/filelists/current/tile_conv_axi_tb.f
C:\Xilinx\Vivado\2024.1\bin\xelab.bat tb_single_conv_tile_axi -s tb_single_conv_tile_axi_sim
C:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_single_conv_tile_axi_sim -runall
```

정상 종료 문구:

```text
PASS: tb_tile_window_path rows=4 windows=104
PASS: tb_single_conv_tile inputs=784 outputs=676 cycles=6690
PASS: tb_single_conv_tile_axi inputs=784 outputs=676 status=0x00000811
```

## 4. Custom IP 패키징

1. PYNQ-Z2 RTL project를 만든다.
2. `rtl/filelists/current/tile_conv_rtl.f`에 적힌 파일만 Design Sources에 추가한다.
3. synthesis top을 `top_single_conv_tile_axi`로 지정한다.
4. **Tools > Create and Package New IP > Package your current project**를 선택한다.
5. IP 이름은 예를 들어 `cnn_tile_accel`, version `1.0`으로 한다.
6. Ports and Interfaces에서 다음 interface를 지정한다.

| Interface | Mode | 신호 prefix |
| --- | --- | --- |
| `S_AXI` | AXI4-Lite Slave | `s_axi_*` |
| `S_AXIS` | AXI4-Stream Slave | `s_axis_*` |
| `M_AXIS` | AXI4-Stream Master | `m_axis_*` |
| `aclk` | clock | 위 세 interface에 associate |
| `aresetn` | active-low reset | `aclk`에 associate |
| `irq` | interrupt | active high |

7. `S_AXIS`와 `M_AXIS`는 4-byte TDATA와 TLAST를 사용한다.
8. `TKEEP` 연결 때문에 interface validation이 실패하면 AXIS Subset Converter를
   넣고 누락된 TKEEP를 all-ones로 만든다.
9. Review and Package에서 error와 critical warning을 해결한 후 IP repository를
   block-design project에 추가한다.

기본 parameter가 이미 타일용 값이므로 크기 parameter를 바꾸지 않는다.

## 5. Block design 구성

추가할 IP:

- ZYNQ7 Processing System
- AXI DMA
- 패키징한 `cnn_tile_accel`
- PS 제어용 AXI SmartConnect/Interconnect
- DMA DDR용 AXI SmartConnect/Interconnect
- Processor System Reset
- 필요 시 `xlconcat`

### 5.1 Zynq PS

- board preset 적용
- `M_AXI_GP0` enable: PS가 DMA와 가속기 AXI-Lite를 제어
- `S_AXI_HP0` enable: DMA가 DDR에 접근
- `FCLK_CLK0 = 100 MHz`
- interrupt를 쓸 경우 `IRQ_F2P` enable

### 5.2 AXI DMA

| 옵션 | 값 |
| --- | --- |
| Scatter Gather | disabled |
| MM2S | enabled |
| S2MM | enabled |
| Micro DMA | disabled |
| Stream width | 32 bit |
| Memory-map width | 32 또는 64 bit |
| DRE | optional; `pynq.allocate` 사용 시 disabled 가능 |

가장 큰 현재 packet은 3136 byte이므로 기본 DMA length 폭으로 충분하다.

### 5.3 연결표

| Source | Destination |
| --- | --- |
| `PS/M_AXI_GP0` | control interconnect input |
| control interconnect output 0 | `axi_dma_0/S_AXI_LITE` |
| control interconnect output 1 | `cnn_tile_accel_0/S_AXI` |
| `axi_dma_0/M_AXI_MM2S` | DDR interconnect input 0 |
| `axi_dma_0/M_AXI_S2MM` | DDR interconnect input 1 |
| DDR interconnect output | `PS/S_AXI_HP0` |
| `axi_dma_0/M_AXIS_MM2S` | `cnn_tile_accel_0/S_AXIS` |
| `cnn_tile_accel_0/M_AXIS` | `axi_dma_0/S_AXIS_S2MM` |

데이터 방향은 반드시 다음과 같다.

```text
PS DDR --MM2S--> accelerator --S2MM--> PS DDR
```

### 5.4 clock/reset

첫 build는 전부 `FCLK_CLK0` 100 MHz 한 domain으로 연결한다.

- 가속기 `aclk`
- DMA의 모든 AXI clock
- 모든 interconnect clock
- `M_AXI_GP0_ACLK`, `S_AXI_HP0_ACLK`
- Processor System Reset의 `slowest_sync_clk`

`FCLK_RESET0_N`을 Processor System Reset에 넣고, 그 블록의
`peripheral_aresetn`을 가속기와 DMA에 연결한다. interconnect reset은
`interconnect_aresetn`에 연결한다. 소프트웨어 GPIO로 `aresetn`을 직접 만들지 않는다.

### 5.5 interrupt

첫 테스트는 polling으로 충분하다. interrupt를 연결하면 DMA MM2S, DMA S2MM,
가속기 `irq`를 `xlconcat`으로 묶어 `IRQ_F2P`에 연결한다. 현재 `irq`는 parameter
load 완료와 tile 완료 모두에서 sticky done과 함께 올라가므로 소프트웨어가 STATUS를
읽어 어느 명령이 끝났는지 판단한다.

## 6. 주소 할당

Address Editor에서 예를 들어 다음처럼 고정한다.

| Slave | Base | Range |
| --- | --- | --- |
| `axi_dma_0/S_AXI_LITE` | `0x4040_0000` | 64 KiB |
| `cnn_tile_accel_0/S_AXI` | `0x43C0_0000` | 64 KiB |

두 DMA memory master의 address space에 PS DDR segment가 보여야 한다.

## 7. 가속기 레지스터

| Offset | 내용 |
| --- | --- |
| `0x00` | CTRL: bit0 RUN_TILE, bit1 CLEAR_DONE, bit2 SOFT_RESET, bit3 LOAD_PARAM |
| `0x04` | STATUS |
| `0x08` | accepted input word count |
| `0x0c` | accepted output word count |
| `0x10` | tile input words = 784 |
| `0x14` | tile output words = 676 |
| `0x18` | error flags |
| `0x1c` | parameter words = 10 |
| `0x20` | total serial input channels = 1~1024 |
| `0x24` | current 0-based input channel index |

ERROR bit:

| Bit | 의미 |
| --- | --- |
| 0 | parameter packet의 early TLAST |
| 1 | parameter 마지막 word의 TLAST 누락 |
| 2 | output count와 TLAST 위치 불일치 |
| 3 | busy 중 명령 또는 parameter 없이 RUN_TILE |
| 4 | input tile의 early TLAST |
| 5 | input tile 마지막 word의 TLAST 누락 |
| 6 | TOTAL_IC가 0이거나 최대값 초과 |

주요 STATUS bit:

| Bit | 의미 |
| --- | --- |
| 0 | idle |
| 1 | parameter loading |
| 2 | tile running |
| 3 | output draining |
| 4 | sticky done |
| 5 | any error |
| 6 | core busy |
| 7 | core done |
| 11 | parameters loaded |
| 15:12 | wrapper state |

## 8. DMA packet 계약

MM2S 한 번에 모든 데이터를 합치지 않는다. `TOTAL_IC`를 먼저 설정한 다음 같은
MM2S channel로 아래 두 DMA transfer를 입력 채널마다 반복한다.

### Transfer A: parameter load

- CTRL bit3 `LOAD_PARAM` 실행
- 10 word / 40 byte
- word 0~8: 하위 8bit에 signed INT8 weight
- word 9: 32bit signed INT32 bias. 첫 입력 채널의 bias만 누적에 사용된다.
- TLAST: word 9

### Transfer B/C: tile run

- 마지막 입력 채널에서만 S2MM를 676 word / 2704 byte buffer로 먼저 arm
- MM2S를 784 word / 3136 byte buffer로 arm
- CTRL bit0 `RUN_TILE` 실행
- MM2S word: row-major 픽셀, 하위 8bit signed INT8
- MM2S TLAST: word 783
- S2MM data: 676개의 signed INT32 accumulator
- S2MM TLAST: output word 675

중간 입력 채널은 PL의 partial-sum BRAM만 갱신하고 S2MM 출력을 만들지 않는다.
각 중간 채널 완료 IRQ 후 `CURRENT_IC` 증가를 확인하고 `CLEAR_DONE`을 실행한 뒤
다음 parameter/tile transfer를 진행한다.

`SOFT_RESET`은 wrapper 상태를 초기화하지만 weight/bias RAM은 지우지 않는다. FPGA
전체 reset 뒤에는 반드시 parameter transfer부터 수행한다.

## 9. Bitstream와 PYNQ 테스트

1. Validate Design에서 error/critical warning을 모두 해결한다.
2. HDL wrapper를 생성한다.
3. Synthesis와 Implementation을 실행한다.
4. 100 MHz clock의 최종 `WNS >= 0`, failing endpoint 0인지 확인한다.
5. bitstream를 생성한다.
6. `.bit`와 `.hwh`를 같은 basename으로 복사한다.
7. 다음 Tcl도 보관한다.

```tcl
write_bd_tcl -force cnn_tile_system_bd.tcl
write_project_tcl -force cnn_tile_system_project.tcl
```

보드에 다음을 복사한다.

- `cnn_tile_system.bit`
- `cnn_tile_system.hwh`
- `sw/pynq/smoke_test_single_conv.py`
- `sw/fixture/single_conv_tile_28/`
- `sw/fixture/multi_ic_conv_tile_28/` (다중 채널 검증 시)

실행:

```bash
python3 smoke_test_single_conv.py \
  --bitstream cnn_tile_system.bit \
  --fixture single_conv_tile_28
```

합격 문구:

```text
PASS: PYNQ-Z2 AXI DMA smoke test input_channels=1 parameters_per_channel=10 inputs_per_channel=784 outputs=676
```

## 10. 전체 feature map 타일링 주의

현재는 valid 3×3이므로 입력 28×28에서 출력 26×26이 나온다. 전체 feature map을
계산할 때 입력 타일의 step은 28이 아니라 26이어야 하며, 인접 입력 타일은 가로·세로
2픽셀 halo가 겹쳐야 한다. 겹침 없이 28씩 건너뛰면 타일 경계의 출력이 누락된다.

YOLOv3-Tiny의 padding=1 계층은 PS가 외곽 halo를 0으로 채우거나 PL에 padding 생성기를
추가해야 원본 크기를 유지한다. 현재 smoke test는 padding=0만 검증한다.

## 11. 현재 제한과 다음 단계

이 bitstream가 성공해도 전체 YOLOv3-Tiny가 완성된 것은 아니다. 다음 기능은 아직
통합되지 않았다.

- 입력 채널 병렬화(`IC_PAR > 1`); 현재 `IC_PAR=1` 순차 누산은 구현됨
- 여러 output channel의 weight/bias 반복 처리
- 별도 1×1 convolution 경로 또는 3×3 datapath 재사용 모드
- INT32→INT8 requantization
- LeakyReLU/linear activation 연결
- MaxPool
- 계층/tile scheduler와 padding/halo 처리

최초 보드 마일스톤의 합격 기준은 위 28×28 fixture의 676개 INT32 결과가 Python
golden과 bit-exact로 일치하는 것이다.

## 12. 담당자가 돌려줄 산출물

- `.bit`, `.hwh`
- block-design Tcl, project Tcl
- Validate Design 결과
- synthesis utilization report
- implementation timing summary
- PYNQ smoke-test 전체 console log
- 사용한 RTL revision 또는 패키징한 exact source ZIP

문제가 생기면 증상만 전달하지 말고 STATUS, STREAM_IN, STREAM_OUT, ERROR 레지스터와
DMA status register를 함께 기록한다.
