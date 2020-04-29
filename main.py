import sys

fgdel = "*.foreground:"
bgdel = "*.background:"
xpath = ".Xresources"

# throw error if no arguments
# maybe default to bg instead of exiting the program?
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

# check if arguments are valid, mostly debug but will be used for error handling
if str(arg1) == valid_args[0] or valid_args[1]:
    print("works")
else:
    print("\nHELP: -bg for background, -fg for foreground")

grad_color = "gibberish"

if str(arg1) == valid_args[0]:
    grad_color = bgdel
    print(grad_color)
elif str(arg1) == valid_args[1]:
    grad_color = fgdel
    print(grad_color)
else:
    print("invalid stuff etc")

#----------#

# calc function outline
# how do i even start manipulating hex?
# add '0x' to the start of the hex color value, then do math as normal, using a int as operand
# it will return a int value, which can then be converted to hex with the hex() function
# ...simple?

#----------#

# open file and search for string function
# this might be the hardest one

# this function doesn't need to be here, it's too complicated, i'll simplify it later
fpath = "testfile"
def openf(f_path, access_mode):
    if access_mode == "r":
        file1 = open(fpath, "r")

    elif access_mode == "rw":
        file1 = open(fpath, "r+")

    elif access_mode == "ar":
        file = open(fpath, "a+")

    else:
        print("invalid access mode, fix it")
        exit(1)

# refactor this mountain of garbage please

#file1 = open('.Xresources')

#bgdel = "*.background:"
#fgdel = "*.foreground:"
#for line in file1:
#    if fgdel in line:
#        line2 = line.replace("#", '0x')
#        line2 = line2.replace(" ", '')
#        line2 = line2.replace("  ", '')
#        line2 = line2.replace(fgdel, '')
#        print(line2)
#        line2 = line2.replace('\n', '')
#        # can't turn hex into int, have to calculate shit before
#        line3 = int(line2, 16) + 500
#        line3 = hex(line3)
#        print(line3)
#
#        print("it finds it")
#file1.close()

# get_hex: takes a file path and a line identifier (depending on which color you want)

# testing get_hex
def get_hex(fpath, color):
    
    file1 = open(fpath)
    for line in file1:
        if color in line:
            line2 = line.replace(color, '')
            line2 = line2.replace("#", '')
            line2 = line2.replace(" ", '')
            line2 = line2.replace("\n", '')
            print(line2)
            file1.close()
            return(line2)
        
        # this doesn't fucking work for some reason, i have no idea
#        else:
#            return("fuck")
#            print("error: couldn't find xresources color in file specified")
#            file1.close()
#            exit(1)

def do_gradient(color, offset, opr):
    if color == "" or offset <= 0:
        print("error: invalid color or invalid offset")
        exit(1)
    elif opr == "add":
        i = int(color, 16)
        i = i + offset
        hexi = hex(i)
        return(hexi)
    elif opr == "sub":
        i = int(color, 16)
        i = i - offset
        hexi = hex(i)
        return(hexi)




grad = get_hex(xpath, grad_color)
print(grad)
test = do_gradient("d2d2d2", 3000, "sub")
print(test)

        

