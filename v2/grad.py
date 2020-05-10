import sys

xpath = '/home/daniel/project/python/xresgrad/v2/.Xresources'

valid_colors = [ "*.foreground:", "*foreground:", "*.background:", "*background:" ]



# What will it return?
def verify(xpath, desired_color):
    with open(xpath, 'r') as file:
        for line in file:
            if desired_color in line:
                return True
        return False



#for i in range(0, len(valid_colors)):
#    if verify(xpath, valid_colors[i]) == True:
#        print("found index " + str(i))
#    else:
#        print("didn't find index " + str(i))
#    ++i
    
def verify2(xpath, color_list):
    if isinstance(color_list, list):
        with open(xpath, 'r') as file:
            for line in file:
                for i in range(0, len(color_list)):
                    if color_list[i] in line:
                        print("found " + color_list[i])
                    ++i

verify2(xpath, valid_colors)
