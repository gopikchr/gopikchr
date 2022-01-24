package main

import (
	"flag"
	"fmt"
	"os"
	"regexp"

	"github.com/gopikchr/gopikchr"
)

/* Testing interface
**
** Generate HTML on standard output that displays both the original
** input text and the rendered SVG for all files named on the command
** line.
 */
func main() {
	var bSvgOnly bool
	var bDontStop bool
	var bDarkMode bool
	flag.BoolVar(&bSvgOnly, "svg-only", false, "Emit raw SVG without the HTML wrapper")
	flag.BoolVar(&bDontStop, "dont-stop", false, "Process all files even if earlier files have errors")
	flag.BoolVar(&bDarkMode, "dark-mode", false, "White-on-Black")

	options := []gopikchr.Option{gopikchr.WithSVGClass("pikchr")}

	exitCode := false /* Whether to return an error */
	zStyle := ""      /* Extra styling */
	zHtmlHdr := `<!DOCTYPE html>
<html lang="en-US">
<head>
<title>PIKCHR Test</title>
<style>
  .hidden {
     position: absolute !important;
     opacity: 0 !important;
     pointer-events: none !important;
     display: none !important;
  }
</style>
<script>
  function toggleHidden(id){
    for(var c of document.getElementById(id).children){
      c.classList.toggle('hidden');
    }
  }
</script>
<meta charset="utf-8">
</head>
<body>
`

	flag.Parse()
	if len(flag.Args()) < 1 {
		usage(os.Args[0])
	}
	if bDarkMode {
		zStyle = "color:white;background-color:black;"
		options = append(options, gopikchr.WithDarkMode())
	}
	if bSvgOnly {
		options = append(options, gopikchr.WithPlaintextErrors())
	}
	for i, arg := range flag.Args() {
		zIn, err := os.ReadFile(arg)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%v\n", err)
			continue
		}
		zOut, w, _, err := gopikchr.Convert(string(zIn), options...)
		if err != nil {
			exitCode = true
		}
		if bSvgOnly {
			fmt.Printf("%s\n", zOut)
		} else {
			if zHtmlHdr != "" {
				fmt.Printf("%s", zHtmlHdr)
				zHtmlHdr = ""
			}
			fmt.Printf("<h1>File %s</h1>\n", arg)
			if err != nil {
				fmt.Printf("<p>ERROR</p>\n%s\n", zOut)
			} else {
				fmt.Printf("<div id=\"svg-%d\" onclick=\"toggleHidden('svg-%d')\">\n", i+1, i+1)
				fmt.Printf("<div style='border:3px solid lightgray;max-width:%dpx;%s'>\n", w, zStyle)
				fmt.Printf("%s</div>\n", zOut)
				fmt.Printf("<pre class='hidden'>")
				print_escape_html(string(zIn))
				fmt.Printf("</pre>\n</div>\n")
			}
		}

		if exitCode && !bDontStop {
			break
		}
	}
	if !bSvgOnly {
		fmt.Printf("</body></html>\n")
	}
	if exitCode {
		os.Exit(1)
	}
}

/* Print a usage comment for the shell and exit. */
func usage(argv0 string) {
	fmt.Fprintf(os.Stderr, "usage: %s [OPTIONS] FILE ...\n", argv0)
	fmt.Fprintf(os.Stderr, "Convert Pikchr input files into SVG.  Filename \"-\" means stdin.\n")
	flag.PrintDefaults()
	os.Exit(1)
}

var html_re = regexp.MustCompile(`[<>&]`)

/* Send text to standard output, but escape HTML markup */
func print_escape_html(z string) {
	z = html_re.ReplaceAllStringFunc(z, func(s string) string {
		switch s {
		case "<":
			return "&lt;"
		case ">":
			return "&gt;"
		case "&":
			return "&amp;"
		default:
			return s
		}
	})
	fmt.Printf("%s", z)
}
