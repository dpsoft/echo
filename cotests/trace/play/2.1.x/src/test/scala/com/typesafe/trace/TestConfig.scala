/**
 * Copyright (C) 2009-2012 Typesafe Inc. <http://www.typesafe.com>
 */
package com.typesafe.trace

import com.typesafe.config.{ Config, ConfigFactory }

object ActionTraceSpecConfig {
  val config: Config = ConfigFactory.parseString("""
      |akka {
      |  # TestEventHandler suppresses "simulated" errors
      |  event-handlers = ["com.typesafe.trace.test.TestEventHandler"]
      |  event-handler-startup-timeout = 10s
      |  loglevel = WARNING
      |  stdout-loglevel = WARNING
      |  actor {
      |    default-dispatcher {
      |      executor = "fork-join-executor"
      |      fork-join-executor {
      |        parallelism-min = 12
      |        parallelism-max = 12
      |      }
      |    }
      |  }
      |}
      |
      |activator {
      |  trace {
      |    enabled = true
      |    traceable {
      |      "*" = on
      |    }
      |    sampling {
      |      "*" = 1
      |    }
      |    futures = off
      |    iteratees = on
      |    use-dispatcher-monitor = off
      |    use-system-metrics-monitor = off
      |    buffer.size-limit = 0
      |    events {
      |      futures = off
      |      iteratees = on
      |    }
      |  }
      |
      |  trace.test.time-factor = 1
      |}""".stripMargin)
}
