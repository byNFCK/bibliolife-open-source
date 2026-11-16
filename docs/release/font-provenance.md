# Font provenance and redistribution

**Status:** All retained bundled fonts have an identified license notice. The legacy Nimbus Android FXL patch is excluded because its exact WOFF grant/conversion provenance could not be established.

## Retained fonts

| Font | Version / files | Copyright / source evidence | License and conditions |
|---|---|---|---|
| Accessible DfA | OTF 1.10; WOFF/WOFF2 1.700 | Orange copyright metadata; WOFF metadata links to the upstream Orange license | SIL OFL 1.1; Reserved Font Name `Accessible-Dfa`. Keep the license and do not use the reserved name for a modified version. |
| iA Writer Duospace | 1.001 TTF (two identical copies) | IBM copyright metadata; Mike Abbink / Bold Monday; modified by Oliver Reichenstein | SIL OFL 1.1; Reserved Font Name `Plex`. Retain IBM Plex/iA notice. |
| Literata | 3.002 variable regular and italic TTF (demo and test-app copies) | Embedded Google Fonts/Literata Project copyright metadata; copies in demo and test-app are duplicates | SIL OFL 1.1; retain Literata copyright and license. |
| Rozel Cut-cut | 1.003 WOFF plus obfuscated test copies | Embedded metadata names Juan Pablo del Peral and Morgane Johan; derived from Alegreya | SIL OFL 1.1; Reserved Font Names `Alegreya` and `Alegreya SC`. Retain the Alegreya OFL text and font-specific attribution. |
| OpenDyslexic | 2.001 OTF copies | All three copies match the author's historical binary at the pinned author commit | Bitstream Vera permission notice plus CC BY 3.0 attribution for Abelardo Gonzalez's changes and additional glyphs. |

## Nimbus exclusion

The eight Nimbus Sans/Roman WOFF files from the optional Android Fonts Patch are not included in this candidate. The exact source release and applicable grant/exception for those converted WOFF files were not established. The patch directory is removed and the web-internals CSS copy configuration excludes it. This is an exclusion decision, not a claim that Nimbus is GPL, OFL or otherwise licensed.

## License files

- `third_party/licenses/AccessibleDfA-OFL-1.1.txt`
- `third_party/licenses/iA-Writer-Duospace-OFL-1.1.txt`
- `third_party/licenses/Literata-OFL.txt`
- `third_party/licenses/Alegreya-OFL-1.1.txt`
- `third_party/licenses/OpenDyslexic-2.001-Bitstream.txt`
- `third_party/licenses/CC-BY-3.0.txt`

## Redistribution conditions

OFL fonts may be bundled and embedded with software, but must not be sold by themselves; modified versions must respect reserved font names and remain under the OFL. The OpenDyslexic binary retains the original Bitstream permission notice and the CC BY 3.0 attribution for the author's changes. Keep these license files with the corresponding font assets.

## Scope

This review establishes the license notices and metadata available in the current source candidate. It is not a legal opinion or a substitute for preserving upstream license files. Any new font, conversion, subset, modification or replacement must be audited separately.
