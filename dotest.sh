#!/usr/bin/env bash
set -euo pipefail

echo 'Generating C'
(cd c; ../../golemon/bin/lemonc pikchr.y; rm pikchr.h)

echo 'Generating Go'
echo ' Running golemon'
(cd internal; ../../golemon/bin/golemon pikchr.y)
echo ' Running go fmt'
(cd internal; go fmt ./pikchr.go)

echo 'Building C'
gcc -DPIKCHR_SHELL=1 -o c/pikchr c/pikchr.c

echo 'Building Go'
go build ./cmd/gopikchr

mkdir -p output

test_all_in_dir () {
    if [[ $# != 1 ]]
    then
        echo "test_all_in_dir wants 1 arg; got $#"
        exit 1
    fi

    echo "Testing files in dir: $1"

    FILES=$(cd $1; ls *.pikchr)

    for file in $FILES
    do
        echo " $file"
        name=${file%.pikchr}
        echo "./c/pikchr $1/$name.pikchr"
        ./c/pikchr $1/$name.pikchr > output/$name-c.html || echo 'ERROR!'
        echo "./gopikchr $1/$name.pikchr"
        ./gopikchr $1/$name.pikchr > output/$name-go.html || echo 'ERROR!'
        echo " - Diffing output for $name.pikchr"
        diff output/$name-c.html output/$name-go.html
    done
}

test_all_in_dir examples
test_all_in_dir tests

echo "DONE: no failures"
