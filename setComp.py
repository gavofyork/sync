#!/usr/bin/python
# Full tag list for any given file.
# Copyright 2005 Joe Wreschnig
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# $Id: mutagen-inspect 3839 2006-09-11 03:34:43Z piman $

import os
import sys
import locale

def main(argv):
    from mutagen import File
    from mutagen.m4a import M4A

    args = argv[1:]

    if not args:
        raise SystemExit(parser.print_help() or 1)

    for filename in args:
        try:
            md = mutagen.m4a.Open(filename)
            if (not md.has_key('----:com.apple.iTunes:COMPILATION')) or md['----:com.apple.iTunes:COMPILATION'] != "1" or (not md.has_key("cpil")) or md['cpil'] != "True":
                md['----:com.apple.iTunes:COMPILATION'] = "1"
                md['cpil'] = "True"
                md.save()
                print filename
        except AttributeError: print "- Unknown file type"
        except KeyboardInterrupt: raise
        except Exception, err: print str(err)

if __name__ == "__main__":
    try: import mutagen
    except ImportError:
        # Run as ./mid3v2 out of tools/
        sys.path.append(os.path.abspath("../"))
        import mutagen
    main(sys.argv)
