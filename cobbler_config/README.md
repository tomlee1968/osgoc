osgops_cobbler: Files for the OSG Operations Cobbler server

Basically speaking, you check this out on cobbler.grid.iu.edu as root, change
to the top-level directory of the repository you just checked out, and type
'make'.  Various kickstart files and snippets will be copied into place,
tarballs will be made and copied into place, etc.  You will probably want to
type 'cobbler sync' after you do this.
