# glfw-craftinfo

Craftinfo for mulle-sde to build [glfw](//github.com/<|GITHUB_USER|>/glfw)

``` bash
mulle-sde dependency add --github <|GITHUB_USER|> glfw
mulle-sde dependency mark glfw singlephase
# mulle-sde dependency set glfw aliases glfw-other
# mulle-sde dependency set glfw include glfw-other.h
# mulle-sde environment --global set MULLE_CRAFT_USE_SCRIPTS glfw-build
```

## Tips

* If you want to define `CFLAGS` use `definition/set/append/CFLAGS` instead of `definition/set/CFLAGS` so that you can still add flags with the environment variable `CFLAGS`. Or use `mulle-sde dependency craftinfo  set --append glfw CFLAGS "-DX=0`
* use `CPPFLAGS` instead of `CFLAGS` to match C++, C and Objective-C
* you can use `definition/set/append0` to append a string without an intervening space
* you can use `definition/set/remove` to remove a definition
