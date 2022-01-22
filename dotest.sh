#!/usr/bin/env bash
set -euo pipefail

# echo 'Building lemonc'
# gcc -o ./bin/lemonc golemon/lemon.c

# echo 'Building lemongo'
# go build -o ./bin/lemongo ./golemon/lemon.go

# echo 'Generating C'
# (cd golemon; ../bin/lemonc pikchr.y)

# echo 'Generating Go'
# bin/lemongo pikchr.y

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
        echo " - C pikchr: $name.pikchr"
        ./c/pikchr $1/$name.pikchr > output/$name-c.html
        echo " - Go pikchr: $name.pikchr"
        ./gopikchr $1/$name.pikchr > output/$name-go.html
        echo " - Diffing output for $name.pikchr"
        diff output/$name-c.html output/$name-go.html
    done
}

test_all_in_dir examples
test_all_in_dir tests
# test_all_in_dir fuzzcases

# FILES=$(cd examples; ls *.pic)

# for file in $FILES
# do
#     name=${file%.pic}
#     echo "C pikchr: $name.pic"
#     bin/pikchr-c examples/$name.pic > examples/$name-c.html
#     echo "Go pikchr: $name.pic"
#     bin/pikchr-go examples/$name.pic > examples/$name-go.html || true
#     echo "Diffing output for $name.pic"
#     diff examples/$name-c.html examples/$name-go.html
# done

# echo 'Diffing output for test.pic'
# diff svg/test-c.html svg/test-go.html
#
# echo 'Diffing output for syntax.pic'
# diff svg/syntax-c.html svg/syntax-go.html
#
# echo 'Diffing output for architecture.pic'
# diff svg/architecture-c.html svg/architecture-go.html
