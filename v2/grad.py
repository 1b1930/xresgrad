import sys, fileinput, subprocess, argparse

xpath = '/home/daniel/.Xresources'

valid_colors = [ "*.foreground:", "*foreground:", "*.background:", "*background:" ]
valid_str_args = [ "bg", "fg" ]
rangestart = 0


# Verifies and, if a line is found, returns that line with the specified color
def verify3(xpath, color):
    if isinstance(color, str):
        with open(xpath, 'r') as file:
            for line in file:
                if color in line:
                    return line
    else:
        return 1

# simply takes a line and strips it so only the hex value is left, then returns that value
def extracthex(line, index):
    line = line.replace(valid_colors[index], '')
    line = line.replace('\t', '')
    line = line.replace(' ', '')
    line = line.replace('#', '')
    line = line.replace('\n', '')
    return line


# Lighten/Darken hex color function by Chase Seibert
def color_variant(hex_color, brightness_offset=1):
#    """ takes a color like #87c95f and produces a lighter or darker variant """
    if len(hex_color) != 7:
        raise Exception("Passed %s into color_variant(), needs to be in #87c95f format." % hex_color)
    rgb_hex = [hex_color[x:x+2] for x in [1, 3, 5]]
    new_rgb_int = [int(hex_value, 16) + brightness_offset for hex_value in rgb_hex]
    new_rgb_int = [min([255, max([0, i])]) for i in new_rgb_int] # make sure new values are between 0 and 255
    # hex() produces "0x88", we want just "88"
    return "#" + "".join([hex(i)[2:] for i in new_rgb_int])


# Appends lines to file, adds proper Xresources syntax
def append1(xpath, line, times):
    with open(xpath, 'a') as file:
        file.write('*.grad' + str(times) + ':\t' + line + '\n')

def appendargb(xpath, transparency):
    with open(xpath, 'a') as file:
        for i in range(2,4):
            if verify3(xpath, valid_colors[i]):
                hexbg = extracthex(verify3(xpath, valid_colors[i]), i)
                file.write('*.backgroundpoly:\t' + '#' + transparency + hexbg)
                break
            else:
                ++i
                



# Checks if arguments given by the user are valid
# I need to learn more about actual error handling, but for now this will do

# using argparse to better structure arguments
# TODO: Integrate into main function

parser = argparse.ArgumentParser(description='Calculates darker or lighter versions of fg or bg xresources color.')
parser.add_argument('--base-color', '-c', type=str, default="fg", help='Color to use as base. DEFAULT: foreground', choices=['fg', 'bg'])
parser.add_argument('--offset', '-o', type=int, default=-10, help='Color offset, higher numbers yield more disparity between gradient steps', nargs='?')
args=parser.parse_args()

if args.base_color not in valid_str_args:
    print(args)
    print("\nERROR: INVALID ARGUMENTS")
    sys.exit(1)
elif args.base_color == valid_str_args[0]:
    rangestart = 2
else:
    rangestart = 0


# delete previous gradient colors, if any
for line in fileinput.input(xpath, inplace=True):
    if "*.grad" in line:
        continue
    if "*.backgroundpoly" in line:
        continue
    print(line, end='')

# Main function
for i in range(rangestart, len(valid_colors)):
    if not verify3(xpath, valid_colors[i]):
        ++i
    else:
        chosen_line = extracthex(verify3(xpath, valid_colors[i]), i)
        for y in range(0,10):
            shit = color_variant("#" + chosen_line, int(args.offset) * y)
            append1(xpath, shit, y)
            print(shit)
            ++y
        appendargb(xpath, 'aa')
        subprocess.call([ './trimfile.sh' ])
        break


