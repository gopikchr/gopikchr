// Package gopikchr is a pure-Go port of the pikchr.org diagram
// generator.
package gopikchr

import (
	"errors"

	"github.com/gopikchr/gopikchr/internal"
)

// Convert converts a pikchr program into SVG, or returns an error
// message.
func Convert(input string, options ...Option) (output string, width int, height int, err error) {
	conf := &config{}
	for _, o := range options {
		o(conf)
	}
	var w, h int
	html := internal.Pikchr(input, conf.class, conf.mFlag, &w, &h)
	if w == -1 {
		return html, 0, 0, Error
	}
	return html, w, h, nil
}

type config struct {
	class string
	mFlag uint
}

// Option is the type of gopikchr options, exported so callers can
// construct slices of options.
type Option func(o *config)

// Error is the error returned from Convert, to signal that an Error
// occurred. It's not actually useful: the error information is
// returned in the output string.
var Error = errors.New("an error occurred converting the pikchr diagram; see output for details")

// WithSVGClass causes the given class to be added to the <svg> markup.
func WithSVGClass(class string) Option {
	return func(o *config) {
		o.class = class
	}
}

// WithPlaintextErrors will cause errors to be reported as text/plain
// instead of text/html.
func WithPlaintextErrors() Option {
	return func(o *config) {
		o.mFlag |= 1
	}
}

// WithDarkMode will cause the colors to be inverted.
func WithDarkMode() Option {
	return func(o *config) {
		o.mFlag |= 2
	}
}

// Version returns the version string for the pikchr library.
func Version() string {
	return internal.PikChrVersion()
}
