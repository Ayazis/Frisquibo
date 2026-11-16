# Water types

`OceanLook` presets for different waters. The light lost per metre (absorption, per colour) follows
the diffuse attenuation of Jerlov's optical water types (Jerlov 1976; approximate values at 650, 550
and 450 nm for red, green and blue). The colours are judged by eye and still need a look on a desktop GPU.

| File | Jerlov type | Where |
|---|---|---|
| `clear_ocean.tres` | I | Open ocean far from land: deep blue, clear to 30 m and more. |
| `coastal.tres` | 3C | Coastal sea and bays: green-blue, a few metres of visibility. |
| `murky.tres` | 9C | Harbours, river mouths, moats, ponds: brown-green, under a metre of visibility. |

They work for lakes and moats too: `Sea.look` takes the same resource (its shader shares the names).
