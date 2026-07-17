# zig.sh

A small script that downloads Zig if necessary and then invokes the Zig binary.

## Usage: `zig.sh`

1. Copy `zig.sh` to your project's directory, i.e. to `<project>/zig.sh`.
2. (OPTIONAL) Create a `<project>/.zig-version` file that contains your desired Zig version (e.g. `master`, `0.16.0`).
3. Replace all direct uses of `zig` with `zig.sh`.

The scripts are intended to be copied _verbatim_ to your projects and then never modified.

### Option: Zig version

Which Zig version you want is configurable.
`zig.sh` looks for the first one of the following to find the desired Zig version:

- A `ZIG_VERSION` environment variable.
- A `.zig-version` file next to the `zig.sh` file.

If no value was found, it assumes that you want the version referred to as `master` at any given time.

> [!NOTE]
> `master` was chosen because otherwise `zig.sh` would have to be updated with every release.

### Option: Force downloads

Force `zig.sh` to always download everything by using `ZIGSH_FORCE_DOWNLOAD`

### Option: Mirror (TODO)

Specify which mirror to use when downloading Zig.
This is done by changing a URL to a `index.json`, which contains the necessary information for downloading Zig.

`zig.sh` does the following (in order) to determine `ZIGSH_INDEX_URL`:

1. If the `ZIGSH_INDEX_URL` environment variable is set, do nothing.
2. If the `ZIGSH_MIRROR` environment variable is set, set `ZIGSH_INDEX_URL` to `${ZIGSH_MIRROR}/index.json`.
3. If the `ZIGSH_MIRRORS` environment variable is set, interpret it as a list of mirrors (separated with either `;` or newline).
   Select one entry at random from this list to be `ZIGSH_MIRROR`.
   Set `ZIGSH_INDEX_URL` to `${ZIGSH_MIRROR}/index.json`.
4. If the `ZIGSH_MIRRORS_TXT` environment variable is set, do the following:
   - If either of the following are true, set `ZIGSH_MIRRORS` to the contents of `https://ziglang.org/download/community-mirrors.txt`:
     - `${ZIGSH_MIRRORS_TXT}` does not exist on the file system.
     - `${ZIGSH_MIRRORS_TXT}` exists, but it is considered too old.
     - `ZIGSH_FORCE_DOWNLOAD` is set.
   - Otherwise, set `ZIGSH_MIRRORS` to the content of `${ZIGSH_MIRRORS_TXT}`, and continue from (3).
5. Set `ZIGSH_MIRRORS_TXT` to be `${ZIG_BASE_DIR}/community-mirrors.txt`, and continue from (4).

## TODO list

- [ ] Is it worth making a `zls.sh`?
- [ ] Perhaps more ways of detecting the desired version.
- [ ] Support community mirrors

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
