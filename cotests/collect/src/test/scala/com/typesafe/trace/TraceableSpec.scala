/**
 *  Copyright (C) 2011-2013 Typesafe, Inc <http://typesafe.com>
 */

package com.typesafe.trace

import com.typesafe.trace.test.EchoCollectSpec
import scala.concurrent.duration._

class Akka20TraceableSpec extends TraceableSpec {
  val createCount = 27
}

class Akka21TraceableSpec extends TraceableSpec {
  val createCount = 10
}

class Akka22TraceableSpec extends TraceableSpec {
  val createCount = 10
}

class Akka23Scala210TraceableSpec extends Akka23TraceableSpec
class Akka23Scala211TraceableSpec extends Akka23TraceableSpec

abstract class Akka23TraceableSpec extends TraceableSpec {
  val createCount = 10
}

abstract class TraceableSpec extends EchoCollectSpec {
  def createCount: Int

  "Traceable" must {

    "trace traceable actors" in {
      eventCheck(expected = createCount + 15) {
        // ignore events
      }
    }

    "not trace untraceable actors" in {
      // give extra time for tracing (not that there should be any)
      eventCheck(expected = 0, delay = 1.second) {
        // no events
      }
    }

    "trace traceable actors created in context" in {
      // give extra time for tracing
      eventCheck(expected = 6, delay = 1.second) {
        // ignore events
      }
    }

    "treat untraceable actors as the empty context" in {
      eventCheck(expected = 2 * createCount + 29) {
        val expectedTraces = 2
        countTraces should be(expectedTraces)

        // no events for untraceable actor

        val untraceableEvents = repository.allEvents.filter(_.annotation match {
          case aa: ActorAnnotation ⇒ aa.info.path contains "/user/untraceable"
          case _                   ⇒ false
        })

        untraceableEvents.size should be(0)
      }
    }

  }
}
