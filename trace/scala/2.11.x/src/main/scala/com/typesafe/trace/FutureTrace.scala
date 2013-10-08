/**
 *  Copyright (C) 2011-2013 Typesafe, Inc <http://typesafe.com>
 */

package com.typesafe.trace

import com.typesafe.trace.util.Uuid
import java.util.concurrent.TimeoutException
import scala.concurrent.duration.Duration
import scala.concurrent.Future
import scala.util.{ Try, Success, Failure }

object FutureTrace {
  val ZeroFutureInfo = FutureInfo(Uuid.zero)
}

object TracedFutureInfo {
  def apply(future: Future[_]): FutureInfo = TraceInfo(future) match {
    case info: FutureInfo ⇒ info
    case _                ⇒ FutureTrace.ZeroFutureInfo
  }
}

/**
 * Tracing events of Futures.
 */
class FutureTrace(trace: Trace) {
  import FutureTrace._

  val futureEvents = trace.settings.events.futures

  def tracingFutures = futureEvents && trace.tracing

  def newInfo(dispatcher: String): FutureInfo = FutureInfo(dispatcher = dispatcher)

  def newTaskInfo(dispatcher: String) = TaskInfo(dispatcher = dispatcher)

  def created(info: FutureInfo): Unit = {
    if (tracingFutures) {
      trace.event(FutureCreated(info))
    }
  }

  def scheduled(info: FutureInfo, taskInfo: TaskInfo): TraceContext = {
    val sampled = sample()
    if (sampled > 0)
      if (futureEvents) trace.branch(FutureScheduled(info, taskInfo), sampled)
      else trace.continue
    else if (trace.within && sampled == 0) TraceContext.NoTrace
    else TraceContext.EmptyTrace
  }

  def runnableStarted(info: TaskInfo): Unit = {
    if (tracingFutures) {
      trace.event(RunnableStarted(info))
    }
  }

  def runnableCompleted(info: TaskInfo): Unit = {
    if (tracingFutures) {
      trace.event(RunnableCompleted(info))
    }
  }

  def completed[T](info: FutureInfo, value: Try[T]): Unit = {
    if (tracingFutures) {
      value match {
        case Success(result)    ⇒ trace.event(FutureSucceeded(info, trace.formatLongMessage(result), TraceInfo(result)))
        case Failure(exception) ⇒ trace.event(FutureFailed(info, trace.formatLongException(exception)))
      }
    }
  }

  def callbackAdded(info: FutureInfo): TraceContext = {
    val sampled = sample()
    if (sampled > 0)
      if (futureEvents) trace.branch(FutureCallbackAdded(info), sampled)
      else trace.continue
    else if (trace.within && sampled == 0) TraceContext.NoTrace
    else TraceContext.EmptyTrace
  }

  def callbackStarted(info: FutureInfo): Unit = {
    if (tracingFutures) {
      trace.event(FutureCallbackStarted(info))
    }
  }

  def callbackCompleted(info: FutureInfo): Unit = {
    if (tracingFutures) {
      trace.event(FutureCallbackCompleted(info))
    }
  }

  def awaited(info: FutureInfo): Unit = {
    if (tracingFutures) {
      trace.event(FutureAwaited(info))
    }
  }

  def timedOut(info: FutureInfo, duration: Duration, exception: TimeoutException): Unit = {
    if (tracingFutures) {
      trace.event(FutureAwaitTimedOut(info, duration.toString))
    }
    // rethrow the exception from here
    throw exception
  }

  def sample(): Int = if (trace.within) trace.sampled else 1
}

class FutureRunnable(runnable: Runnable, tracer: ExecutionContextTracer, context: TraceContext, taskInfo: TaskInfo) extends Runnable with TraceInfo {
  def info: Info = taskInfo

  def run: Unit = {
    tracer.trace.local.start(context)
    tracer.future.runnableStarted(taskInfo)
    try {
      runnable.run()
    } finally {
      tracer.future.runnableCompleted(taskInfo)
      tracer.trace.local.end()
    }
  }
}

class FutureCallback[T, U](func: Try[T] ⇒ U, tracer: ExecutionContextTracer, context: TraceContext, futureInfo: FutureInfo)
  extends Function1[Try[T], U] with TraceInfo {

  def info: Info = futureInfo

  def apply(value: Try[T]): U = {
    tracer.trace.local.start(context)
    tracer.future.callbackStarted(futureInfo)
    try {
      func(value)
    } finally {
      tracer.future.callbackCompleted(futureInfo)
      tracer.trace.local.end()
    }
  }
}
