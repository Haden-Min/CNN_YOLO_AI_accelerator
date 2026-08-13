# Golden Model Workspace

`sw/golden` keeps the Phase 1 golden-model work in one place.

## Directory Roles

- `model/`: bit-exact Python reference models that define expected numeric
  behavior.
- `script/`: command-line tools that generate or convert fixtures using the
  reference models.

The committed fixture data lives under `sw/fixture/<fixture_id>/` so the golden
model, helper scripts, and fixture data stay in the software workspace. Generated
RTL memory files go to `sw/fixture/generated/` and are ignored by Git.

## Phase 1 Commands

Run from the repository root:

```powershell
python sw/golden/script/generate_single_conv_fixture.py --fixture single_conv_001
python sw/golden/script/generate_single_conv_fixture.py --fixture single_conv_tile_28
python sw/golden/script/generate_single_conv_fixture.py --fixture single_conv_tile_16
python sw/golden/script/generate_single_conv_fixture.py --fixture multi_ic_conv_tile_28
python sw/golden/model/conv2d_int8_reference.py --fixture sw/fixture/single_conv_001 --check-only
python sw/golden/script/generate_rtl_mem.py --fixture sw/fixture/single_conv_001
python tests/rtl/compare_conv_output.py --fixture sw/fixture/single_conv_001 --actual sw/fixture/single_conv_001/expected_acc_int32.hex
```

`single_conv_tile_28` and `single_conv_tile_16` use the same deterministic
input formula, weights, and bias for the tile-size comparison.
`multi_ic_conv_tile_28` uses three CHW input channels and verifies that bias is
added once while all channel convolutions are accumulated into one INT32 tile.
