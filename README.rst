==============================
The Ren'Py Visual Novel Engine
==============================

https://www.renpy.org

Ren'Py development takes place on the ``master`` branch, and occasionally
on feature branches.


Getting Started
===============

Ren'Py depends on a number of Python modules written in Cython and C. For
changes to Ren'Py that only involve Python modules, you can use the modules
found in the latest nightly build. Otherwise, you'll have to compile the
modules yourself.

The development scripts assume a POSIX-like platform. The scripts should run
on Linux or macOS, and can be made to run on Windows using an environment
like MSYS.

Nightly Build
-------------

Nightly builds can be downloaded from:

   https://nightly.renpy.org

Note that the latest nightly build is at the bottom of the list. Once you've
unpacked the nightly, change into this repository, and run::

    ./after_checkout.sh <path-to-nightly>

Once this script completes, you should be able to run Ren'Py using renpy.sh,
renpy.app, or renpy.exe, as appropriate for your platform.

If the current nightly build doesn't work, please wait 24 hours for a new
build to occur. If that build still doesn't work, contact Tom (`pytom at bishoujo.us`,
or @renpytom on twitter) to find out what's wrong.

The ``doc`` symlink will dangle until documentation is built, as described
below.

Compiling the Modules
----------------------

Building the modules requires you have the many dependencies installed on
your system. 

On Ubuntu and Debian, these dependencies can be installed with
the command::

    sudo apt install virtualenvwrapper python3-dev libavcodec-dev libavformat-dev \
        libswresample-dev libswscale-dev libharfbuzz-dev libfreetype6-dev libfribidi-dev libsdl2-dev \
        libsdl2-image-dev libsdl2-gfx-dev libsdl2-mixer-dev libsdl2-ttf-dev libjpeg-dev

On FreeBSD::
    
    sudo pkg install python2 python3 python310 py39-virtualenv py310-setuptools py310-wheel \
        ffmpeg gstreamer1-libav gstreamer1-plugins gstreamer1-plugins-good freetype2 fribidi \
        gstreamer1-plugins-bad gstreamer1-plugins-ugly sdl2 sdl2_image sdl2_gfx sdl2_mixer \
        sdl2_ttf jpeg-turbo harfbuzz

Ren'Py requires SDL_image 2.6 or greater. If your distribution doesn't include
that version, you'll need to download it from:

    https://github.com/libsdl-org/SDL_image/tree/SDL2

Official Ren'py Developer Recommendation
----------------------------------------

We strongly suggest installing the Ren'Py modules into a Python
virtualenv. To create a new virtualenv, open a new terminal and run::

    . /usr/share/virtualenvwrapper/virtualenvwrapper.sh
    mkvirtualenv renpy

To return to this virtualenv later, run::

    . /usr/share/virtualenvwrapper/virtualenvwrapper.sh
    workon renpy

FreeBSD Porter Recommendation
-----------------------------

I strongly recommend a slightly different approach due to Python conflicts found on
FreeBSD 14.0 while porting the engine. Some major system packages (such as your Window Manager,
Desktop Environment and some maintenance tools installed by default if you use any GUI 
applications) will break if you install both `py39-setuptools` and `py39-wheel` on your 
system at the time of this port. All of this will be done in the root directory of this 
source tree::
    
    export VENV="./tmp/virtualenv.py3"
    python3 -m virtualenv -p "/usr/local/bin/python3.10" $VENV

After activating the virtualenv, install additional dependencies::

    python3 -m pip install -U cython future six typing pefile requests ecdsa

Then, install pygame_sdl2 by running the following commands::

    git clone https://www.github.com/renpy/pygame_sdl2
    pushd pygame_sdl2
    python setup.py install
    python setup.py install_headers
    popd

Next, set RENPY_DEPS_INSTALL To a \:-separated (\;-separated on Windows)
list of paths containing the dependencies, and RENPY_CYTHON to the name
of the cython command::

    export RENPY_DEPS_INSTALL="/usr:/usr/lib/$(gcc -dumpmachine)/"
    export RENPY_CYTHON=cython

Finally, use setup.py in the Ren'Py ``module`` directory to compile and
install the modules that support Ren'Py::

    pushd module
    python setup.py install
    popd

Ren'Py will be installed into the activated virtualenv. It can then be run
using the command::

    python renpy.py


Documentation
=============

Building
--------

Building the documentation requires Ren'Py to work. You'll either need to
link in a nightly build, or compile the modules as described above. You'll
also need the `Sphinx <https://www.sphinx-doc.org>`_ documentation generator.
If you have pip working, install Sphinx using::

    python3 -m pip install -U sphinx sphinx_rtd_theme sphinx_rtd_dark_mode

Once Sphinx is installed, change into the ``sphinx`` directory inside the
Ren'Py checkout and run::

    ./build.sh

Format
------

Ren'Py's documentation consists of reStructuredText files found in sphinx/source, and
generated documentation found in function docstrings scattered throughout the code. Do
not edit the files in sphinx/source/inc directly, as they will be overwritten.

Docstrings may include tags on the first few lines:

\:doc: `section` `kind`
    Indicates that this function should be documented. `section` gives
    the name of the include file the function will be documented in, while
    `kind` indicates the kind of object to be documented (one of ``function``,
    ``method`` or ``class``. If omitted, `kind` will be auto-detected.
\:name: `name`
    The name of the function to be documented. Function names are usually
    detected, so this is only necessary when a function has multiple aliases.
\:args: `args`
    This overrides the detected argument list. It can be used if some arguments
    to the function are deprecated.

For example::

    def warp_speed(factor, transwarp=False):
        """
        :doc: warp
        :name: renpy.warp_speed
        :args: (factor)

        Exceeds the speed of light.
        """

        renpy.engine.warp_drive.engage(factor)


Translating
===========

For best practices when it comes to translating the launcher and template
game, please read:

https://lemmasoft.renai.us/forums/viewtopic.php?p=321603#p321603


Contributing
============

For bug fixes, documentation improvements, and simple changes, just
make a pull request. For more complex changes, it might make sense
to file an issue first so we can discuss the design.

License
=======

For the complete licensing terms, please read:

https://www.renpy.org/doc/html/license.html

For the FreeBSD port license, see LICENSE.rst
