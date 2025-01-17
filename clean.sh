#!/bin/bash

git status | sed '1,/use "git add <file>..." to include in what will be committed/d' | sed '/^$/q' | xargs rm -rf
