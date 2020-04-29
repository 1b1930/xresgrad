import sys

# throw error if no arguments
if len(sys.argv) <= 1:
    print("ERROR: Specify which color you want to use as base for the gradients!")
    exit(1)

# simple argument test
arg1 = sys.argv[1]
# arg2 = sys.argv[2]

# DEBUG #
# prints all arguments and numbers em
for i in range(1, len(sys.argv)):
    print(sys.argv[i], i)

# count the number of arguments
# len(sys.argv)
# shouldn't let argument number surpass how many args i want

#----------#

# For simplicity, i'll only accept one argument and two possibilities for now
valid_args = ["-bg", "-fg"]
if str(arg1) == valid_args[0]:
    print("works")
else:
    print("doesn't work")

