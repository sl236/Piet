Piet
====

Piet assembler and compiler

    ./piet-assembler somefile.piet | pnmtopng > out.png
    ./piet-compiler somefile.script | piet-assembler | pnmtopng > out.png
    ./piet-assembler assembler-samples/fizzbuzz.piet | pnmtopng > fizzbuzz.png && interpreter/piet fizzbuzz.png


See http://www.toothycat.net/wiki/wiki.pl?MoonShadow/Piet for further documentation and samples

For convenience, a fork of Marc Majcher's Piet interpreter is included. 
See http://www.majcher.com/code/piet/Piet-Interpreter.html for documentation and updates.