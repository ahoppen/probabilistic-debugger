# Probabilistic Debugger

This project implements a proof-of-concept-debugger for probabilistic programming languages.

## Implemented language

It currently handles a very simple toy language (called SL for **S**imple **L**anguage) with a C-like syntax that has the following well-known constructs:
* Variable declarations: `int x = y + 2`
* Variable assignments: `x = x + 1`
* Expressions with the following well-known operators: `+`, `-`, `==`, ` `<`
* Discrete probability distributions: `int x = discrete({1: 0.2: 2: 0.8})` (`x` gets assigned `1` with probability `0.2` and `2` with probability `0.8`)
* If-Statements: `if (x < 3) { ... } else { ... }`
* While-Loops: `while (x < 3) { ... }`
* Observe statements: `observe(x < 3)`

## Testing the project

### On macOS, using Xcode

Install Xcode and open the project by opening `Package.swift`. To run the tests, select Product -> Test (Cmd-U)

### On macOS, using Command line tools

In terminal `cd` to this project, then execute `swift test` to run the tests
