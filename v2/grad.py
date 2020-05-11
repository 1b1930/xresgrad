import sys

xpath = '/home/daniel/project/python/xresgrad/v2/.Xresources'

valid_colors = [ "*.foreground:", "*foreground:", "*.background:", "*background:" ]
valid_str_args = [ "-bg", "-fg" ]
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


# Checks if arguments given by the user are valid
# I need to learn more about actual error handling, but for now this will do
if sys.argv[1] not in valid_str_args:
    print("ERROR: INVALID ARGUMENTS")
    sys.exit(1)
elif sys.argv[1] == valid_str_args[0]:
    rangestart = 2
else:
    rangestart = 0

# Main function
for i in range(rangestart, len(valid_colors)):
    if not verify3(xpath, valid_colors[i]):
        ++i
    else:
        chosen_line = extracthex(verify3(xpath, valid_colors[i]), i)
        for y in range(0,10):
            shit = color_variant("#" + chosen_line, int(sys.argv[2]) * y)
            print(shit)
            ++y
        break




        





