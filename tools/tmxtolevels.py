import sys
from os import walk
from xml.etree import ElementTree


WIDTH = 16
HEIGHT = 14
ENTITY_FORMAT =  "{{ entityType = {entityType}, x = {x}, y = {y}, width = {width}, height = {height}, props = {{ {props} }} }}"
WALL_FORMAT =  "{{ {x}, {y}, {width}, {height} }}"

LEVELS = {
    'demo.tmx': 1,
}

def convert_tiles(map_root):
    map_tiles_text = None
    for child in map_root:
        if child.tag == "layer":
            map_tiles_text = child[0].text
            break

    if not map_tiles_text:
        print("Could not find tiles in map file. Is this a Tiled .tmx file?")
        return

    output = "tiles = \""
    # Start at 1 since maps are 14 high but vertically centered.
    for y in range(0, HEIGHT):
        lineout = ""
        tiles_line = map_tiles_text.splitlines()[y + 1]
        for x in range(0, WIDTH):
            tile = int(tiles_line.split(",")[x])
            if tile > 0:
                # Trim '0x' prefix.
                hextile = str(hex(tile - 1))[2:]
                # Decimal tile indices must be converted
                # to two digit hex values.
                if len(hextile) < 2:
                    hextile = '0' + hextile
                lineout += hextile
            else:
                lineout += '00'

        output += lineout

    return output + "\","


def convert_entities(map_root):
    entities_group = None
    for child in map_root:
        if child.tag == "objectgroup" and child.attrib["name"] == "entities":
            entities_group = child
            break

    if not entities_group:
        print("Could not find entities in map file. Is this a Tiled .tmx file?")
        return

    output = "entities = {"
    for entity in entities_group:
        props = ""
        if len(entity):
            props = "".join([
                "{name} = \"{value}\",".format(
                    name=prop.attrib['name'],
                    value=prop.attrib['value'],
                )
                for prop in entity[0]
            ])
        lineout = ENTITY_FORMAT.format(
            entityType='"{}"'.format(entity.attrib['type']),
            x=entity.attrib['x'],
            y=entity.attrib['y'],
            width=entity.attrib['width'],
            height=entity.attrib['height'],
            props=props,
        )
        output += lineout + ",\n"

    return output + "},"


def convert_walls(map_root):
    walls_group = None
    for child in map_root:
        if child.tag == "objectgroup" and child.attrib["name"] == "walls":
            walls_group = child
            break

    if not walls_group:
        print("Could not find walls in map file. Is this a Tiled .tmx file?")
        return

    output = "walls = {"
    for wall in walls_group:
        props = ""
        # List instead of dict to save tokens
        lineout = WALL_FORMAT.format(
            x=wall.attrib['x'],
            y=wall.attrib['y'],
            width=wall.attrib['width'],
            height=wall.attrib['height'],
        )
        output += lineout + ",\n"

    return output + "},"


def main(tmx_directory, levels_filename):
    output = "local LEVELS = {"
    _, _, tmx_filenames = next(walk(tmx_directory))

    for tmx_filename in tmx_filenames:
        map_root = ElementTree.parse(tmx_directory + tmx_filename).getroot()
        output += "[{}] = {{".format(LEVELS[tmx_filename]) + convert_tiles(map_root) + convert_entities(map_root) + convert_walls(map_root) +  "},"

    output = output + "}\n"

    with open(levels_filename, 'w') as outfile:
        outfile.write(output)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
