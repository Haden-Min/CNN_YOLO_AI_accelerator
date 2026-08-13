# GitHub 업로드 가이드

대상 저장소: <https://github.com/Haden-Min/CNN_YOLO_AI_accelerator>

현재 작업 브랜치는 `codex/axi-wrapper-pynq-dma`이며, 원격 기본 브랜치는 `main`이다.

## 업로드할 내용

- `rtl/`: 타일 convolution RTL, serial-IC partial-sum BRAM, AXI wrapper와 테스트
- `sw/`: 다중 IC golden fixture와 PYNQ 채널별 DMA 실행 코드
- `scripts/`: Vivado OOC 합성 스크립트
- `reports/`: 타일 크기별 timing/utilization 결과
- `docs/`: 구조, 블록 디자인, 외주 모듈 규격 문서
- `README.md`: 프로젝트 사용법과 현재 구현 상태

`.Xil/`, `xsim.dir/`, `*.wdb`, `*.jou`, `*.log`, `*.dcp`, methodology report,
Python cache 등 재생성 가능한 로컬 산출물은 `.gitignore`에 의해 업로드되지 않는다.

## PowerShell에서 실행할 명령어

아래 명령은 순서대로 실행한다.

```powershell
Set-Location -LiteralPath "C:\Users\hanyu\Documents\CNN Accelerator\CNN_YOLO_AI_accelerator"

git branch --show-current
git remote -v
git status --short

git add -- .gitignore README.md GITHUB_UPLOAD.md
git add -- docs rtl
git add -- sw/golden sw/pynq sw/fixture/multi_ic_conv_tile_28
git add -- reports/tile-size-comparison.md reports/tile_conv_multi_ic_ooc/summary.md
git add -- reports/tile_conv_multi_ic_ooc/timing_summary.rpt reports/tile_conv_multi_ic_ooc/utilization_hierarchical.rpt

git status --short
git diff --cached --check
git diff --cached --stat

git commit -m "Add serial input-channel accumulation"
git push -u origin codex/axi-wrapper-pynq-dma
```

`git diff --cached --check`가 아무것도 출력하지 않으면 공백 오류 검사를 통과한 것이다.

## main 브랜치에 반영

푸시가 끝나면 다음 주소를 열어 Pull Request를 생성하고 병합한다.

<https://github.com/Haden-Min/CNN_YOLO_AI_accelerator/compare/main...codex/axi-wrapper-pynq-dma?expand=1>

권장 제목:

```text
Add serial input-channel accumulation
```

병합 후 로컬 `main`을 최신 상태로 맞추려면 다음을 실행한다.

```powershell
git switch main
git pull origin main
```

## 인증 오류가 발생할 때

`git push` 과정에서 GitHub 로그인을 요구하면 표시되는 브라우저 인증을 완료한다. GitHub CLI를 사용할 경우에는 다음 명령으로 다시 로그인할 수 있다.

```powershell
& "C:\Program Files\GitHub CLI\gh.exe" auth login -h github.com
```
