preface, this code is part of a much larger library that handles lots of other things like stats gathering, syncing between folders, notifications, and more, i ripped this out, and briefly tested, but works very well in my existing system.


### what this does.
this pulls data from transmission, looks for anything not registered, and deletes it. transmission cleaner


### to install

install cpanm
https://metacpan.org/pod/App::cpanminus

cpanm FindBin Log::Log4perl JSON Mojo::Transmission Config::Simple

or use cpan install then the above minus cpanm

edit the settings.conf and include the one host, or multiple if you have different seed boxes.

if you don't want to go through all that, you can try the super old one that watches the log of transmission, but no promises there.
