#!/bin/bash

cat -s ~/.Xresources >> ~/.Xresources2
rm ~/.Xresources
mv ~/.Xresources2 ~/.Xresources
