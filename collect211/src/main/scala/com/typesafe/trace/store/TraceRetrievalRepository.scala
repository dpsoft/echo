/**
 *  Copyright (C) 2011-2013 Typesafe <http://typesafe.com/>
 */
package com.typesafe.trace.store

import com.typesafe.trace.TraceEvent
import com.typesafe.trace.uuid.UUID

trait TraceRetrievalRepository {
  def trace(id: UUID): Seq[TraceEvent]
  def event(id: UUID): Option[TraceEvent]
  def events(ids: Seq[UUID]): Seq[TraceEvent]
  def findEventsWithinTimePeriod(startTime: Long, endTime: Long, offset: Int = 1, limit: Int = 100): Seq[TraceEvent]
}
