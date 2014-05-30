/**
 * Copyright (C) 2009-2011 Scalable Solutions AB <http://scalablesolutions.se>
 */

package com.typesafe.trace

import akka.actor._
import akka.event.Logging
import akka.event.Logging.{ Error, Warning }
import com.typesafe.trace.test.EchoTraceSpec
import com.typesafe.trace.util.ExpectedFailureException

class Akka23Scala210EventStreamSpec extends EchoTraceSpec {

  "Event stream tracing" must {

    "capture all errors and warnings" in {
      val cause = new ExpectedFailureException("")
      val errorMsg = "Expected error"
      val warningMsg = "Expected warning"

      system.eventStream.publish(Error(cause, "EventStreamSpec", getClass, errorMsg))
      system.eventStream.publish(Warning("EventStreamSpec", getClass, warningMsg))

      system.log.error(cause, errorMsg)
      system.log.warning(warningMsg)

      val log1 = Logging(system, getClass)
      log1.error(cause, errorMsg)
      log1.warning(warningMsg)

      val log2 = Logging(system.eventStream, getClass)
      log2.error(cause, errorMsg)
      log2.warning(warningMsg)

      eventCheck()
    }

  }
}
