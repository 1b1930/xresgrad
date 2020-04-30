import sys, os, fileinput
from colorsys import rgb_to_hls, hls_to_rgb
from webcolors import rgb_to_hex, hex_to_rgb

# string that will be deleted from line extracted from xresources
# necessary to extract correct hex value
fgdel = "*.foreground:"
bgdel = "*.background:"

# xresources path, will change for release
xpath = "/home/daniel/.Xresources"

# maps argument variables to cmd arguments
arg1 = sys.argv[1]
arg2 = sys.argv[2]
arg3 = sys.argv[3]

# turns offset argument into an int (from str)
# necessary for offset range error checking
arg2 = int(arg2)

# this can possibly go, i don't know, i'll think about it, maybe
valid_args = [ "-bg", "-fg" ]

# Self-explanatory, basic error checking
if arg1 not in valid_args:
    print("ERROR: Invalid color argument")
    exit(1)
elif arg2 < -30000 or arg2 > 30000:
    print("ERROR: Invalid offset range")
    exit(1)
elif arg3 not in ["add", "sub"]:
    print("ERROR: Invalid operator, valid operators: \"add\" and \"sub\"")
    exit(1)

# Don't know if this needs to be here, but it gives me an error if i delete it so fuck it
grad_color = "gibberish"

# stores either bgdel or fgdel into it's actual variable to be used by functions
if str(arg1) == valid_args[0]:
    grad_color = bgdel
elif str(arg1) == valid_args[1]:
    grad_color = fgdel

#
#
#   function definitions
#
#

# get_hex: takes a file path and a line identifier (depending on which color you want)

def get_hex(fpath, color):
    
    file1 = open(fpath)
    for line in file1:
        if color in line:
            line2 = line.replace(color, '')
            line2 = line2.replace("#", '')
            line2 = line2.replace(" ", '')
            line2 = line2.replace("\n", '')
            file1.close()
            return(line2)



# takes a color (in hex!), it's offset (how much to add or subtract from it) and a operator (str: "add" or "sub")

def do_gradient(hexcolor, offset, opr):
    if opr == "add":
        i = int(hexcolor, 16)
        i = i + offset
        hexi = hex(i)
        return(hexi)
    
    elif opr == "sub":
        i = int(hexcolor, 16)
        i = i - offset
        hexi = hex(i)
        return(hexi)



# very simple function that appends a line to the end of the file specified
def append_to_file(line, fname):
    with open(fname, "a") as file1:
        file1.write(line)
        file1.write("\n")
    return(0)


def delete_multiple_lines(original_file, line_numbers):
    """In a file, delete the lines at line number in given list"""
    is_skipped = False
    counter = 0
    # Create name of dummy / temporary file
    dummy_file = original_file + '.bak'
    # Open original file in read only mode and dummy file in write mode
    with open(original_file, 'r') as read_obj, open(dummy_file, 'w') as write_obj:
        # Line by line copy data from original file to dummy file
        for line in read_obj:
            # If current line number exist in list then skip copying that line
            if counter not in line_numbers:
                write_obj.write(line)
            else:
                is_skipped = True
                counter += 1
    # If any line is skipped then rename dummy file as original file
    if is_skipped:
        os.remove(original_file)
        os.rename(dummy_file, original_file)
    else:
        os.remove(dummy_file)


## main function, kindof


#rgbt = hex_to_rgb('#' + get_hex(xpath, grad_color))
#print(rgbt)




def color_variant(hex_color, brightness_offset):
    # """ takes a color like #87c95f and produces a lighter or darker variant """
    if len(hex_color) != 7:
        raise Exception("Passed %s into color_variant(), needs to be in #87c95f format." % hex_color)
    rgb_hex = [hex_color[x:x+2] for x in [1, 3, 5]]
    new_rgb_int = [int(hex_value, 16) + brightness_offset for hex_value in rgb_hex]
    new_rgb_int = [min([255, max([0, i])]) for i in new_rgb_int] # make sure new values are between 0 and 255
    # hex() produces "0x88", we want just "88"
    return "#" + "".join([hex(i)[2:] for i in new_rgb_int])










# should put this shit inside a function
counter = 0
for line in fileinput.input(xpath, inplace=True):
    if not counter:
        if line.startswith('! GRADIENTS') or line.startswith('*.grad'):
            counter = 4;
        else:
            print(line, end='')
    else:
        counter -= 1

with open(xpath, "a") as file1:
    file1.write("\n! GRADIENTS\n")

for i in range(0,10):
    hexc = get_hex(xpath, grad_color)
    hexc2 = color_variant("#" + hexc, i * arg2)
    hexc_line = "*.grad" + str(i) + ":\t" + hexc2
    print(hexc_line)
    append_to_file(hexc_line, xpath)
    ++i

