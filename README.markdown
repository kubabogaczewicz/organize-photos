# Ogranize photos

This is a helper script I've written just for my personal usage. It helps me organize photos according to [my method](#organizing).

I use Apple's Photos app and so a lot of assumptions about files, extensions, exif tags etc. are about what Photos exports or how MacOS works. 

## Usage

Export your photos and movies into a folder. If exporting movies does not save creation date, try exporting unmodified original.

Once all files are in a folder run `organize.rb`.

Organize only copies images - I don't want to destroy any data. With APFS copying should not move any data anyway, so there is no point not to copy.

## Requirements

Before even installing required gems (`$ bundle install`) you must install libexif and exiftool

```
$ brew install libexif exiftool
$ bundle
```

libexif is required by gem exif - which is very fast in reading exif tags from images but cannot read .mov files

exiftool is a lot slower (the gem - `mini_exiftool` - just calls shell to execute `exiftool` cmd) but can read pretty much anything that might contain metadata.

## Organizing

All photos and movies are exported into yearly folders. For each year I just dump all the files into a flat structure. All files are renamed according to creation date.

Example:

```
→ tree Photobank        
/Users/kuba/Photobank
├── 2016
│   ├── 2016-12-26\ 14-40-03.mov
│   └── 2016-12-31\ 11-00-33.jpg
└── 2017
    ├── 2017-01-23\ 09-53-42.jpg
    └── 2017-01-23\ 09-57-10.jpg

2 directories, 4 files
  
```

In the past Aperture was happy to export into this format, unfortunatelly Apple's Photos cannot do that. 
