# gopikchr: a Go port of pikchr

A direct port of [pikchr.org](https://pikchr.org)'s
[pikchr.y](https://pikchr.org/home/file?name=pikchr.y&amp;ci=tip) to
Go, by hand.

## Why?

Why would anyone hand-port almost 12,000 lines of C to Go? There's no
good reason. I just like Go, and I like pikchr, and I wanted to use
pikchr cleanly in Go, and on my blog, using
[Hugo](https://gohugo.io/).

Perhaps it's just having to constantly make trade-offs and value
expediency at work that leaves us with an irrational, curmudgeony
desire to dive all the way down the yak-shaving stack, and **do things
right, dammit!**. Consider `gopikchr` a
[gift](https://apenwarr.ca/log/20211229).

## State

There are probably bugs.

Things work well enough to properly convert files in `examples/`, and
`tests/`, but I'm sure there are still bugs lurking.

Everything is currently in `impl/` and `cmd/pikchr`; it remains to add
a clean Go interface in this root directory.

Pull requests are welcome: I currently intend no support for this
project, but if you're obscure enough to want a Go port of pikchr,
then we share some strange kind of kinship, and I welcome your
contributions.

## Goals

- Add pikchr support to my blog (which means adding it to Hugo (which
  means adding it to goldmark)).
- Keep the code structure in `pikchr.y` as close to the original as
  possible, to make tracking and applying future changes as
  straight-forward as possible. This means the code is often *very*
  C-like, and not very Goish.
- Convert to Go idioms only where the conversion remains clear.

## Methodology

This code was hand-ported from the C code, on top of a hand-port of
the [Lemon Parser](https://www.sqlite.org/lemon.html). It is clearly C
code, transliterated to Go. I converted pointers to bytes and pointer
math on byte pointers to `[]byte` in Go, but otherwise everything is
left alone as much as possible.

# TODOs

- [ ] Add a clean Go interface in the root directory
- [ ] Create a github action that follows the rss feed for changes to
      `pikchr.y` and creates issues.
- [ ] (Maybe) Set up fuzzing

## Contributors

- [@zellyn](https://github.com/zellyn)
