import sys

xpath = '/home/daniel/project/python/xresgrad/v2/.Xresources'

valid_colors = [ "*.foreground:", "*foreground:", "*.background:", "*background:" ]
valid_str_args = [ "-bg", "-fg" ]


def verify3(xpath, color):
    if isinstance(color, str):
        with open(xpath, 'r') as file:
            for line in file:
                if color in line:
                    return line
    else:
        print >> sys.stderr, "ERROR: COLOR VAR NOT STRING, YOU FUCKED UP SOMEWHERE!"
        sys.exit(1)


def extracthex(line, index):
    line = line.replace(valid_colors[index], '')
    line = line.replace('\t', '')
    line = line.replace(' ', '')
    line = line.replace('#', '')
    line = line.replace('\n', '')
    print(line)


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



for i in range(1,2):
    if sys.argv[i] not in valid_str_args:
        print >> sys.stderr, "ERROR: INVALID ARGUMENT(S)"
        sys.exit(1)
    ++i



