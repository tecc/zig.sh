# zig.sh

A small script that downloads Zig if necessary and then invokes the Zig binary.

## Usage: `zig.sh`

1. Copy `zig.sh` to your project's directory, i.e. to `<project>/zig.sh`.
2. (OPTIONAL) Create a `<project>/.zig-version` file that contains your desired Zig version (e.g. `0.16.0`, `0.17.0-dev.1387+01b60634c`).
3. Replace all direct uses of `zig` with `zig.sh`.

The scripts are intended to be copied _verbatim_ to your projects and then never modified.

Please read the `zig.sh`.

## TODO list

- [x] ZLS installation
- [x] Autodetection of Zig version `build.zig.zon`'s `minimum_zig_version`
- [x] Support community mirrors
- [x] Verify minisign signatures

## Licence

The licence text may be found in [./LICENCE](./LICENCE), but it is reproduced here because why not?

```
MIT License

Copyright (c) 2026 tecc

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
