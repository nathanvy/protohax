# Protohax

These are my solutions to the Protohackers challenges, in Common Lisp.  I make use of several sbcl-specific extensions (threading, mainly) so do not expect this code to be portable to other implementations without a bit of porting.

I may in the future migrate SBCL threads to Bordeaux Threads which are portable, but no guarantees.

https://protohackers.com

## Running
Unless otherwise noted, or unless you see ASDF system definitions, you should assume each individual challenge is meant to be loaded from the command line, as such:

```
$ cd 01-smoketest
$ sbcl --load smoketest.lisp
 * (init)
 ```
 
 
