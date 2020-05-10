import sys

xpath = '/home/daniel/project/python/xresgrad/v2/.Xresources'

valid_colors = [ "*.foreground:", "*foreground:", "*.background:", "*background:" ]

def verify3(xpath, color):
    if isinstance(color, str):
        with open(xpath, 'r') as file:
            for line in file:
                if color in line:
                    return line
    else:
        print >> sys.stderr, "ERROR: COLOR VAR NOT STRING!"


def extracthex(line, index):
    line = line.replace(valid_colors[index], '')
    line = line.replace('\t', '')
    line = line.replace(' ', '')
    line = line.replace('#', '')
    line = line.replace('\n', '')
    print(line)


extracthex(verify3(xpath, valid_colors[0]), 0)
