# likeOS
* likeOS, a "clean" OS for opencomputers without a shell, with low system requirements, designed for automation (robots, NPP control),
* there is a smart auto-loading of libraries
* the OS kernel contains a simple api for working with graphics that will help you draw interfaces.  
this api will allow you to work on multiple monitors, and the api itself will take care of GPU switching.  
however, to work on multiple monitors, you should use multiple graphics cards (it will be faster this way)
* if you want to use the OS on your computer, i can recommend a liked distribution (https://github.com/igorkl/liked) the official distribution of likeOS for computers and tablets

## the structure of the filesystem
* /system/core - the OS kernel, it's better not to go there unless absolutely necessary.
* /system - the distribution files, when creating the distribution of the program and library, drop them here
* /data - os and userdata (the location of the user's files depends on the distribution, but they are always located in the data folder in liked, this is /data/userdata)
* /init.lua - the basic loader, referring to the kernel loader "/system/bootloader.lua" this script is able to load the bootmanager from the appropriate folder