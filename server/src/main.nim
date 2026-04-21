import std/random

import config, network

when isMainModule:
  randomize()
  runServer(defaultConfig())
