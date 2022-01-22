# gopikchr: a Go port of pikchr

A direct port of [pikchr.org](https://pikchr.org)'s
[pikchr.y](https://pikchr.org/home/file?name=pikchr.y&amp;ci=tip) to
Go, by hand.

## State

There are bugs.

Things work well enough to properly convert files in `examples/`, and
I'm working my way through `tests/`, fixing errors.

Everything is currently in `impl/` and `cmd/pikchr`; it remains to add
a clean Go interface in this root directory.

Pull requests are welcome: I currently intend no support for this
project, but if you're obscure enough to want a Go port of pikchr,
then we share a strange kind of kinship, and I welcome your
contributions.

## Goals

- Add pikchr support to my blog (which means adding it to Hugo (which
  means adding it to goldmark)).
- Keep the code structure in `pikchr.y` as close to the original as
  possible, to make tracking and applying future changes as
  straight-forward as possible. This means the code is often *very*
  C-like, and not very Goish.
- Convert to Go idioms only where the conversion remains clear.

## Depends on

This project depends on the Go port of the [Lemon
Parser](https://www.sqlite.org/lemon.html),
[golemon](https://github.com/gopikchr/golemon).

# TODOs

- [ ] Add a clean Go interface in the root directory
- [ ] Get all the files in `tests/` working
- [ ] Set up fuzzing
- [ ] Create a github action that follows the rss feed for changes to
      `pikchr.y` and creates issues.

## Contributors

- [@zellyn](https://github.com/zellyn)
