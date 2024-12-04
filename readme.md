# MaintainWindowsImagesWHD

This is a Windows image maintenance tool for modern Windows editions. Modern as in newer than Vista/2008. Unmaintained for years, it's only here for historical curiosity. You should really consider using OSDBuilder or WIMwitch. This was conceived in an era when these tools just didn't exist, I probably wrote first version sometime in 2014.

This is not a generic tool, it was built for internal use and very specific environment and requirements. Therefor it does very specific stuff that is probably not convenient for your needs. I once had a plan to rewrite it what I named "workflow engine" that would have worked very similarly to OSDbuilder. However this version worked well enough in it's quite static way and other than some function templates and documents about design, nothing happened. Then I pivoted away from image management for a few years and when I returned to the field, current tools had become public.

Seriously, don't use this tool for anything else than academic study.

Why the strange name? Well the tool never had any name per se. It was just the name of script from start to end of maintenance. Common nickname was ImageBuilder.

I'm going to assume you know internals of how Windows servicing stack works

## Workflow

### Throw WIMs in correct folder
One image per WIM. Basically any WIM from Vista/2008 SP2 and up will work but 7SP1, 8.1U4, various early W10 releases and corresponding server versions have ran the most. WS2012 is the hardest case as you at some point needed to integrate every SS update in specific order up to a certain point (about 7 updates if I remember correctly). If you didn't, image would lock and no further integrations would be possible. I no longer have the list and it would be pretty hard to rebuild.
### Throw updates in another folder
There are subfolders SS and LP. SS is servicing stack. You better patch it up first as some updates will just not work without specific SS versions. LP-s need to be applied before updates as updates often contain updated resource files. More on this later
### Throw Appx and feature config files in third folder
Appx config became only a thing with W10. You didn't really need it in W81, as you could throw out everything and system worked fine. In W10 some core utils became Appx and you had to be more careful.
Features just turns things off and on as you like.

Probably some more stuff, look at the code.