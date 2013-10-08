/**
 *  Copyright (C) 2011-2013 Typesafe, Inc <http://typesafe.com>
 */

package com.typesafe.trace;

import akka.actor.ActorCell;
import akka.actor.ActorPath;
import akka.actor.ActorRef;
import akka.actor.ActorRefProvider;
import akka.actor.ActorSelection;
import akka.actor.ActorSystem;
import akka.actor.ActorSystemImpl;
import akka.actor.Deploy;
import akka.actor.InternalActorRef;
import akka.actor.LocalActorRefProvider;
import akka.actor.MinimalActorRef;
import akka.actor.Props;
import akka.actor.ScalaActorRef;
import akka.actor.Scheduler;
import akka.actor.UnstartedCell;
import akka.dispatch.Dispatchers;
import akka.dispatch.Envelope;
import akka.dispatch.Mailbox;
import akka.dispatch.MailboxType;
import akka.dispatch.MessageDispatcher;
import akka.dispatch.sysmsg.Failed;
import akka.dispatch.sysmsg.SystemMessage;
import akka.event.EventStream;
import akka.event.SubchannelClassification;
import akka.pattern.AskSupport;
import akka.pattern.PromiseActorRef;
import akka.routing.NoRouter;
import akka.routing.RoutedActorCell;
import akka.util.Timeout;
import com.typesafe.trace.util.Uuid;
import com.typesafe.config.Config;
import scala.concurrent.duration.FiniteDuration;
import scala.concurrent.ExecutionContext;
import scala.concurrent.Future;
import scala.Option;

privileged aspect ActorTraceAspect {

  // ----------------------------------------------------
  // Tracer attached to actor system
  // ----------------------------------------------------

  declare parents: ActorSystem implements WithTracer;

  private volatile ActorSystemTracer ActorSystem._atmos$tracer;

  private ActorSystemTracer ActorSystem.atmos$tracer() {
    return _atmos$tracer;
  }

  private void ActorSystem.atmos$tracer(ActorSystemTracer tracer) {
    _atmos$tracer = tracer;
  }

  public Tracer ActorSystem.tracer() {
    return (Tracer) _atmos$tracer;
  }

  public boolean enabled(ActorSystemTracer tracer) {
    return tracer != null && tracer.enabled();
  }

  public boolean disabled(ActorSystemTracer tracer) {
    return tracer == null || !tracer.enabled();
  }

  // attach new tracer to system

  before(ActorSystemImpl system, String name, Config config, ClassLoader classLoader):
    execution(akka.actor.ActorSystemImpl.new(..)) &&
    this(system) &&
    args(name, config, classLoader)
  {
    ActorSystemTracer tracer = ActorSystemTracer.create(name, config, classLoader);
    system.atmos$tracer(tracer);
    if (enabled(tracer)) {
      tracer.actor().systemStarted(System.currentTimeMillis());
    }
  }

  // system start - wrap in an empty trace context

  Object around(ActorSystemImpl system):
    execution(* akka.actor.ActorSystemImpl.start(..)) &&
    this(system)
  {
    ActorSystemTracer tracer = system.atmos$tracer();
    if (disabled(tracer)) return proceed(system);
    tracer.trace().local().start(TraceContext.EmptyTrace());
    Object result = proceed(system);
    tracer.trace().local().end();
    return result;
  }

  // system shutdown

  after(ActorSystemImpl system):
    execution(* akka.actor.ActorSystemImpl.shutdown(..)) &&
    this(system)
  {
    ActorSystemTracer tracer = system.atmos$tracer();
    if (enabled(tracer)) {
      tracer.shutdown(system);
    }
  }

  // ----------------------------------------------------
  // Tracer attached to dispatchers
  // ----------------------------------------------------

  private volatile ActorSystemTracer Dispatchers._atmos$tracer;

  private ActorSystemTracer Dispatchers.atmos$tracer() {
    return _atmos$tracer;
  }

  private void Dispatchers.atmos$tracer(ActorSystemTracer tracer) {
    _atmos$tracer = tracer;
  }

  private volatile ActorSystemTracer MessageDispatcher._atmos$tracer;

  private ActorSystemTracer MessageDispatcher.atmos$tracer() {
    return _atmos$tracer;
  }

  private void MessageDispatcher.atmos$tracer(ActorSystemTracer tracer) {
    _atmos$tracer = tracer;
  }

  before(Dispatchers dispatchers, ActorSystemImpl system):
    execution(akka.dispatch.Dispatchers.new(..)) &&
    this(dispatchers) &&
    cflow(execution(akka.actor.ActorSystemImpl.new(..)) && this(system))
  {
    dispatchers.atmos$tracer(system.atmos$tracer());
  }

  after(Dispatchers dispatchers) returning(MessageDispatcher dispatcher):
    execution(* akka.dispatch.Dispatchers.lookup(..)) &&
    this(dispatchers)
  {
    dispatcher.atmos$tracer(dispatchers.atmos$tracer());
  }

  // ----------------------------------------------------
  // Dispatcher startup and shutdown
  // ----------------------------------------------------

  after(MessageDispatcher dispatcher):
    call(* akka.dispatch.ExecutorServiceFactory.createExecutorService(..)) &&
    cflow((execution(* akka.dispatch.MessageDispatcher.registerForExecution(..)) ||
           execution(* akka.dispatch.MessageDispatcher.executeTask(..))) &&
           this(dispatcher))
  {
    ActorSystemTracer tracer = dispatcher.atmos$tracer();
    if (enabled(tracer)) {
      tracer.dispatcher().started(dispatcher);
    }
  }

  after(MessageDispatcher dispatcher):
    execution(* akka.dispatch.MessageDispatcher.shutdown(..)) &&
    this(dispatcher)
  {
    ActorSystemTracer tracer = dispatcher.atmos$tracer();
    if (enabled(tracer)) {
      tracer.dispatcher().shutdown(dispatcher);
    }
  }

  // ----------------------------------------------------
  // Tracer attached to mailbox
  // ----------------------------------------------------

  private volatile ActorSystemTracer Mailbox._atmos$tracer;

  private ActorSystemTracer Mailbox.atmos$tracer() {
    return _atmos$tracer;
  }

  private void Mailbox.atmos$tracer(ActorSystemTracer tracer) {
    _atmos$tracer = tracer;
  }

  after(MessageDispatcher dispatcher) returning(Mailbox mailbox):
    execution(* akka.dispatch.MessageDispatcher+.createMailbox(..)) &&
    this(dispatcher)
  {
    mailbox.atmos$tracer(dispatcher.atmos$tracer());
  }

  // ----------------------------------------------------
  // Tracer attached to actor ref provider
  // ----------------------------------------------------

  declare parents: LocalActorRefProvider implements WithTracer;

  private volatile ActorSystemTracer LocalActorRefProvider._atmos$tracer;

  private ActorSystemTracer LocalActorRefProvider.atmos$tracer() {
    return _atmos$tracer;
  }

  private void LocalActorRefProvider.atmos$tracer(ActorSystemTracer tracer) {
    _atmos$tracer = tracer;
  }

  public Tracer LocalActorRefProvider.tracer() {
    return (Tracer) _atmos$tracer;
  }

  // attach the tracer to local actor ref provider

  before(LocalActorRefProvider provider, ActorSystemImpl system):
    execution(* akka.actor.LocalActorRefProvider.init(..)) &&
    this(provider) &&
    args(system)
  {
    provider.atmos$tracer(system.atmos$tracer());
  }

  // ----------------------------------------------------
  // Actor ref tracing metadata
  // ----------------------------------------------------

  declare parents: ActorRef implements TraceInfo;

  // tracer

  private volatile ActorSystemTracer ActorRef._atmos$tracer;

  public ActorSystemTracer ActorRef.atmos$tracer() {
    return _atmos$tracer;
  }

  public void ActorRef.atmos$tracer(ActorSystemTracer tracer) {
    _atmos$tracer = tracer;
  }

  // identifier

  private volatile String ActorRef._atmos$identifier;

  public String ActorRef.atmos$identifier() {
    return _atmos$identifier;
  }

  public void ActorRef.atmos$identifier(String identifier) {
    _atmos$identifier = identifier;
  }

  // traceable

  private volatile boolean ActorRef._atmos$traceable = false;

  public boolean ActorRef.atmos$traceable() {
    return _atmos$traceable;
  }

  public void ActorRef.atmos$traceable(boolean traceable) {
    _atmos$traceable = traceable;
  }

  // actor info

  private volatile ActorInfo ActorRef._atmos$info;

  public ActorInfo ActorRef.atmos$info() {
    return _atmos$info;
  }

  public void ActorRef.atmos$info(ActorInfo info) {
    _atmos$info = info;
  }

  public Info ActorRef.info() {
    return (Info) this._atmos$info;
  }

  // ----------------------------------------------------
  // Actor creation tracing
  // ----------------------------------------------------

  // top-level requested and created events

  ActorRef around(ActorSystemImpl system, Props props, String name):
    execution(* akka.actor.ActorSystemImpl.systemActorOf(..)) &&
    this(system) &&
    args(props, name)
  {
    ActorSystemTracer tracer = system.atmos$tracer();
    ActorRef guardian = system.systemGuardian();

    if (disabled(tracer) || name == null) return proceed(system, props, name);

    String requestedIdentifier = tracer.actor().identifier(guardian.path().child(name));
    boolean requestedTraceable = tracer.actor().traceable(requestedIdentifier);

    TraceContext context;
    if (guardian.atmos$traceable() && requestedTraceable) {
      context = tracer.actor().requestedTopLevelActor(guardian.atmos$identifier(), guardian.atmos$info(), name);
    } else {
      context = TraceContext.NoTrace();
    }

    tracer.trace().local().start(context);
    ActorRef actorRef = proceed(system, props, name);
    if (requestedTraceable) tracer.actor().createdTopLevelActor(actorRef.atmos$info());
    tracer.trace().local().end();
    return actorRef;
  }

  ActorRef around(ActorSystemImpl system, Props props, String name):
    execution(* akka.actor.ActorSystemImpl.actorOf(..)) &&
    this(system) &&
    args(props, name)
  {
    ActorSystemTracer tracer = system.atmos$tracer();
    ActorRef guardian = system.guardian();

    if (disabled(tracer) || name == null) return proceed(system, props, name);

    String requestedIdentifier = tracer.actor().identifier(guardian.path().child(name));
    boolean requestedTraceable = tracer.actor().traceable(requestedIdentifier);

    TraceContext context;
    if (guardian.atmos$traceable() && requestedTraceable) {
      context = tracer.actor().requestedTopLevelActor(guardian.atmos$identifier(), guardian.atmos$info(), name);
    } else {
      context = TraceContext.NoTrace();
    }

    tracer.trace().local().start(context);
    ActorRef actorRef = proceed(system, props, name);
    if (requestedTraceable) tracer.actor().createdTopLevelActor(actorRef.atmos$info());
    tracer.trace().local().end();
    return actorRef;
  }

  ActorRef around(ActorSystemImpl system, Props props):
    execution(* akka.actor.ActorSystemImpl.actorOf(..)) &&
    this(system) &&
    args(props)
  {
    ActorSystemTracer tracer = system.atmos$tracer();
    ActorRef guardian = system.guardian();

    if (disabled(tracer)) return proceed(system, props);

    String name = Traceable.RandomPlaceholder();
    String requestedIdentifier = tracer.actor().identifier(guardian.path().child(name));
    boolean requestedTraceable = tracer.actor().traceable(requestedIdentifier);

    TraceContext context;
    if (guardian.atmos$traceable() && requestedTraceable) {
      context = tracer.actor().requestedTopLevelActor(guardian.atmos$identifier(), guardian.atmos$info(), name);
    } else {
      context = TraceContext.NoTrace();
    }

    tracer.trace().local().start(context);
    ActorRef actorRef = proceed(system, props);
    if (requestedTraceable) tracer.actor().createdTopLevelActor(actorRef.atmos$info());
    tracer.trace().local().end();
    return actorRef;
  }

  // actor requested and created events

  InternalActorRef around(ActorRefProvider provider, ActorSystemImpl system, Props props, InternalActorRef supervisor,
    ActorPath path, boolean systemService, Option<Deploy> deploy, boolean lookupDeploy, boolean async):
    execution(* akka.actor.LocalActorRefProvider.actorOf(..)) &&
    this(provider) &&
    args(system, props, supervisor, path, systemService, deploy, lookupDeploy, async)
  {
    ActorSystemTracer tracer = system.atmos$tracer();

    if (disabled(tracer) || !supervisor.atmos$traceable()) return proceed(provider, system, props, supervisor, path, systemService, deploy, lookupDeploy, async);

    String requestedIdentifier = tracer.actor().identifier(path);
    boolean requestedTraceable = tracer.actor().traceable(requestedIdentifier);
    if (!requestedTraceable) return proceed(provider, system, props, supervisor, path, systemService, deploy, lookupDeploy, async);

    boolean router = !(props.deploy().routerConfig() instanceof NoRouter);
    ActorInfo info = tracer.actor().info(path, props.dispatcher(), false, router);
    TraceContext context = tracer.actor().requested(supervisor.atmos$info(), info);
    tracer.trace().local().start(context);
    InternalActorRef child = proceed(provider, system, props, supervisor, path, systemService, deploy, lookupDeploy, async);
    tracer.actor().created(child.atmos$info());
    tracer.trace().local().end();
    return child;
  }

  // attach metadata to newly created actor

  before(ActorRef actorRef, ActorSystemImpl system, Props props, MessageDispatcher dispatcher, MailboxType mailboxType, InternalActorRef supervisor, ActorPath path):
    execution(akka.actor.ActorRefWithCell+.new(..)) &&
    this(actorRef) &&
    args(system, props, dispatcher, mailboxType, supervisor, path)
  {
    ActorSystemTracer tracer = system.atmos$tracer();
    actorRef.atmos$tracer(tracer);
    if (enabled(tracer)) {
      String identifier = tracer.actor().identifier(path);
      actorRef.atmos$identifier(identifier);
      boolean traceable = tracer.actor().traceable(identifier);
      actorRef.atmos$traceable(traceable);
      if (traceable) {
        boolean router = !(props.deploy().routerConfig() instanceof NoRouter);
        ActorInfo info = tracer.actor().info(path, props.dispatcher(), false, router);
        actorRef.atmos$info(info);
      }
    }
  }

  // ----------------------------------------------------
  // Trace context transfer with system message
  // ----------------------------------------------------

  private volatile TraceContext SystemMessage._atmos$trace;

  public TraceContext SystemMessage.atmos$trace() {
    return _atmos$trace;
  }

  public void SystemMessage.atmos$trace(TraceContext context) {
    _atmos$trace = context;
  }

  // ----------------------------------------------------
  // Actor system message send tracing
  // ----------------------------------------------------

  before(Mailbox mailbox, ActorRef actorRef, SystemMessage message):
    execution(* akka.dispatch.Mailbox+.systemEnqueue(..)) &&
    this(mailbox) &&
    args(actorRef, message)
  {
    ActorSystemTracer tracer = actorRef.atmos$tracer();
    if (enabled(tracer)) {
      // create similar actor failed events to earlier Akka versions
      if (message instanceof Failed) {
        Failed failed = (Failed) message;
        ActorRef child = failed.child();
        if (child != null && child.atmos$traceable()) {
          TraceContext context = tracer.actor().failed(child.atmos$info(), failed.cause(), actorRef.atmos$info());
          message.atmos$trace(context);
        }
      } else if (actorRef.atmos$traceable()) {
        TraceContext context = tracer.actor().message().sysMsgDispatched(actorRef.atmos$info(), message);
        message.atmos$trace(context);
      }
    }
  }

  // ----------------------------------------------------
  // Actor system message processing tracing
  // ----------------------------------------------------

  Object around(ActorCell actorCell, SystemMessage message):
    execution(* akka.actor.ActorCell.systemInvoke(..)) &&
    this(actorCell) &&
    args(message)
  {
    ActorRef actorRef = (ActorRef) actorCell.self();
    ActorSystemTracer tracer = actorRef.atmos$tracer();
    TraceContext context = message.atmos$trace();

    if (disabled(tracer) || !actorRef.atmos$traceable() || (context == null))
      return proceed(actorCell, message);

    ActorInfo info = actorRef.atmos$info();

    // set the trace context from the system message
    tracer.trace().local().start(context);
    tracer.actor().message().sysMsgReceived(info, message);
    Object result = proceed(actorCell, message);
    tracer.actor().message().sysMsgCompleted(info, message);
    tracer.trace().local().end();
    return result;
  }

  // ----------------------------------------------------
  // Transfer trace context with envelope
  // ----------------------------------------------------

  private volatile TraceContext Envelope._atmos$trace = TraceContext.ZeroTrace();

  private TraceContext Envelope.atmos$trace() {
    return _atmos$trace;
  }

  private void Envelope.atmos$trace(TraceContext context) {
    _atmos$trace = context;
  }

  // ----------------------------------------------------
  // Actor message send tracing
  // ----------------------------------------------------

  after(ActorRef actorRef, Envelope envelope, Object message, ActorRef sender):
    execution(akka.dispatch.Envelope.new(..)) &&
    this(envelope) &&
    args(message, sender) &&
    cflow(execution(* akka.actor.ActorRefWithCell+.$bang(..)) && this(actorRef))
  {
    ActorSystemTracer tracer = actorRef.atmos$tracer();
    if (enabled(tracer) && actorRef.atmos$traceable()) {
      ActorInfo senderInfo = (sender != null && sender.atmos$traceable()) ? sender.atmos$info() : null;
      TraceContext context = tracer.actor().told(actorRef.atmos$identifier(), actorRef.atmos$info(), message, senderInfo);
      envelope.atmos$trace(context);
    }
  }

  // ----------------------------------------------------
  // Actor message processing tracing
  // ----------------------------------------------------

  Object around(ActorCell actorCell, Envelope envelope):
    execution(* akka.actor.ActorCell.invoke(..)) &&
    this(actorCell) &&
    args(envelope)
  {
    ActorRef actorRef = (ActorRef) actorCell.self();
    ActorSystemTracer tracer = actorRef.atmos$tracer();
    TraceContext context = envelope.atmos$trace();

    if (disabled(tracer) || !actorRef.atmos$traceable() || (context == null))
      return proceed(actorCell, envelope);

    ActorInfo info = actorRef.atmos$info();
    Object message = envelope.message();

    tracer.trace().local().start(context);
    tracer.actor().message().received(info, message);
    Object result = proceed(actorCell, envelope);
    tracer.actor().message().completed(info, message);
    tracer.trace().local().end();
    return result;
  }

  // ----------------------------------------------------
  // Ask pattern tracing
  // ----------------------------------------------------

  // attach actor ref metadata to promise actor ref

  before(PromiseActorRef actorRef, ActorRefProvider provider):
    execution(akka.pattern.PromiseActorRef.new(..)) &&
    this(actorRef) &&
    args(provider, ..)
  {
    if (provider instanceof WithTracer) {
      ActorSystemTracer tracer = (ActorSystemTracer) ((WithTracer) provider).tracer();
      actorRef.atmos$tracer(tracer);
      if (enabled(tracer)) {
        ActorPath path = actorRef.path();
        String identifier = tracer.actor().identifier(path);
        actorRef.atmos$identifier(identifier);
        boolean traceable = tracer.trace().active();
        actorRef.atmos$traceable(traceable);
        if (traceable) {
          ActorInfo info = tracer.actor().info(path, null, false, false);
          actorRef.atmos$info(info);
        }
      }
    }
  }

  // promise actor created

  after(PromiseActorRef actorRef):
    execution(akka.pattern.PromiseActorRef.new(..)) &&
    this(actorRef)
  {
    ActorSystemTracer tracer = actorRef.atmos$tracer();
    if (enabled(tracer) && actorRef.atmos$traceable()) {
      tracer.actor().tempCreated(actorRef.atmos$info());
    }
  }

  // wrap pattern.ask with a branched asked event

  Future<Object> around(ActorRef actorRef, Object message, Timeout timeout):
    execution(* akka.pattern.AskableActorRef$.ask$extension(..)) &&
    args(actorRef, message, timeout)
  {
    ActorSystemTracer tracer = actorRef.atmos$tracer();

    if (disabled(tracer)) return proceed(actorRef, message, timeout);

    TraceContext context = TraceContext.EmptyTrace();

    if (actorRef.atmos$traceable()) {
      context = tracer.actor().asked(actorRef.atmos$identifier(), actorRef.atmos$info(), message);
    }

    tracer.trace().local().start(context);
    Future<Object> future = proceed(actorRef, message, timeout);
    tracer.trace().local().end();
    return future;
  }

  // promise actor ref message processing

  Object around(PromiseActorRef actorRef, Object message, ActorRef sender):
    execution(* akka.pattern.PromiseActorRef.$bang(..)) &&
    this(actorRef) &&
    args(message, sender)
  {
    ActorSystemTracer tracer = actorRef.atmos$tracer();

    if (disabled(tracer) || !actorRef.atmos$traceable()) return proceed(actorRef, message, sender);

    ActorInfo info = actorRef.atmos$info();
    ActorInfo senderInfo = (sender != null && sender.atmos$traceable()) ? sender.atmos$info() : null;
    TraceContext context = tracer.actor().tempTold(actorRef.atmos$identifier(), info, message, senderInfo);
    tracer.trace().local().start(context);
    tracer.actor().message().tempReceived(info, message);
    Object result = proceed(actorRef, message, sender);
    tracer.actor().message().tempCompleted(info, message);
    tracer.trace().local().end();
    return result;
  }

  // promise actor ref stop

  after(PromiseActorRef actorRef):
    execution(* akka.pattern.PromiseActorRef.stop(..)) &&
    this(actorRef)
  {
    ActorSystemTracer tracer = actorRef.atmos$tracer();
    if (enabled(tracer) && actorRef.atmos$traceable()) {
      tracer.actor().tempStopped(actorRef.atmos$info());
    }
  }

  // ----------------------------------------------------
  // Scheduler tracing
  // ----------------------------------------------------

  // attach tracer to scheduler

  private volatile ActorSystemTracer Scheduler._atmos$tracer;

  private ActorSystemTracer Scheduler.atmos$tracer() {
    return _atmos$tracer;
  }

  private void Scheduler.atmos$tracer(ActorSystemTracer tracer) {
    _atmos$tracer = tracer;
  }

  after(ActorSystemImpl system) returning(Scheduler scheduler):
    execution(* akka.actor.ActorSystemImpl.createScheduler(..)) &&
    this(system)
  {
    scheduler.atmos$tracer(system.atmos$tracer());
  }

  // attach tracer and info to scheduler timeout

  private volatile ActorSystemTracer akka.actor.Cancellable._atmos$tracer;

  public ActorSystemTracer akka.actor.Cancellable.atmos$tracer() {
    return _atmos$tracer;
  }

  public void akka.actor.Cancellable.atmos$tracer(ActorSystemTracer tracer) {
    _atmos$tracer = tracer;
  }

  private volatile TaskInfo akka.actor.Cancellable._atmos$info;

  private TaskInfo akka.actor.Cancellable.atmos$info() {
    return _atmos$info;
  }

  private void akka.actor.Cancellable.atmos$info(TaskInfo info) {
    _atmos$info = info;
  }

  // schedule once tracing

  akka.actor.Cancellable around(Scheduler scheduler, FiniteDuration delay, Runnable runnable, ExecutionContext executor):
    execution(* akka.actor.Scheduler+.scheduleOnce(..)) &&
    this(scheduler) &&
    args(delay, runnable, executor)
  {
    ActorSystemTracer tracer = scheduler.atmos$tracer();
    if (disabled(tracer)) return proceed(scheduler, delay, runnable, executor);
    TaskInfo info = tracer.scheduler().newInfo(executor.getClass().getName());
    TraceContext context = tracer.scheduler().scheduledOnce(info, delay);
    TracedUnscheduledRunnable tracedRunnable = new TracedUnscheduledRunnable(runnable, context, info);
    akka.actor.Cancellable cancellable = proceed(scheduler, delay, tracedRunnable, executor);
    cancellable.atmos$tracer(scheduler.atmos$tracer());
    cancellable.atmos$info(info);
    return cancellable;
  }

  // scheduled task cancelled tracing

  after(akka.actor.Cancellable cancellable) returning (boolean cancelled):
    execution(* akka.actor.Cancellable.cancel(..)) &&
    this(cancellable)
  {
    ActorSystemTracer tracer = cancellable.atmos$tracer();
    if (enabled(tracer) && tracer.trace().sampled() > 0) {
      TaskInfo info = cancellable.atmos$info();
      if (info != null && cancelled) {
        tracer.scheduler().cancelled(info);
      }
    }
  }

  // ----------------------------------------------------
  // Event stream tracing
  // ----------------------------------------------------

  // attach tracer to event stream

  private volatile ActorSystemTracer EventStream._atmos$tracer;

  private ActorSystemTracer EventStream.atmos$tracer() {
    return _atmos$tracer;
  }

  private void EventStream.atmos$tracer(ActorSystemTracer tracer) {
    _atmos$tracer = tracer;
  }

  before(ActorSystemImpl system, EventStream eventStream):
    execution(akka.event.EventStream.new(..)) &&
    this(eventStream) &&
    cflow(execution(akka.actor.ActorSystemImpl.new(..)) && this(system))
  {
    eventStream.atmos$tracer(system.atmos$tracer());
  }

  // event stream publish tracing

  after(SubchannelClassification eventBus, Object event):
    execution(* akka.event.SubchannelClassification$class.publish(..)) &&
    args(eventBus, event)
  {
    if (eventBus instanceof EventStream) {
      EventStream eventStream = (EventStream) eventBus;
      ActorSystemTracer tracer = eventStream.atmos$tracer();
      if (enabled(tracer)) {
        tracer.eventStream().published(event);
      }
    }
  }

  // ----------------------------------------------------
  // Empty local actor ref tracing
  // ----------------------------------------------------

  // attach metadata to newly created empty local actor refs
  // used to check traceability for event stream dead letters

  before(ActorRef actorRef, ActorRefProvider provider, ActorPath path, EventStream eventStream):
    execution(akka.actor.EmptyLocalActorRef+.new(..)) &&
    this(actorRef) &&
    args(provider, path, eventStream)
  {
    ActorSystemTracer tracer = eventStream.atmos$tracer();
    actorRef.atmos$tracer(tracer);
    if (enabled(tracer)) {
      String identifier = tracer.actor().identifier(path);
      actorRef.atmos$identifier(identifier);
      boolean traceable = tracer.actor().traceable(identifier);
      actorRef.atmos$traceable(traceable);
      if (traceable) {
        ActorInfo info = tracer.actor().info(path, "", false, false);
        actorRef.atmos$info(info);
      }
    }
  }

  // ----------------------------------------------------
  // Routed actor tracing
  // ----------------------------------------------------

  // continue the trace context for routed actor ref sends

  Object around(RoutedActorCell actorCell, Envelope envelope):
    execution(* akka.routing.RoutedActorCell.sendMessage(..)) &&
    this(actorCell) &&
    args(envelope)
  {
    ActorRef actorRef = (ActorRef) actorCell.self();
    ActorSystemTracer tracer = actorRef.atmos$tracer();

    if (disabled(tracer) || !actorRef.atmos$traceable()) return proceed(actorCell, envelope);

    TraceContext context = envelope.atmos$trace();
    tracer.trace().local().start(context);
    Object result = proceed(actorCell, envelope);
    tracer.trace().local().end();
    return result;
  }

  // ----------------------------------------------------
  // Actor selection tracing
  // ----------------------------------------------------

  declare parents: ActorSelection implements TraceInfo;

  // tracer

  private volatile ActorSystemTracer ActorSelection._atmos$tracer = null;

  public ActorSystemTracer ActorSelection.atmos$tracer() {
    return _atmos$tracer;
  }

  public void ActorSelection.atmos$tracer(ActorSystemTracer tracer) {
    _atmos$tracer = tracer;
  }

  // traceable

  private volatile boolean ActorSelection._atmos$traceable = false;

  public boolean ActorSelection.atmos$traceable() {
    return _atmos$traceable;
  }

  public void ActorSelection.atmos$traceable(boolean traceable) {
    _atmos$traceable = traceable;
  }

  // info

  private volatile ActorSelectionInfo ActorSelection._atmos$info = null;

  public ActorSelectionInfo ActorSelection.atmos$info() {
    return _atmos$info;
  }

  public void ActorSelection.atmos$info(ActorSelectionInfo info) {
    _atmos$info = info;
  }

  public Info ActorSelection.info() {
    return (Info) this._atmos$info;
  }

  // attach metadata to actor selections

  after() returning(ActorSelection selection):
    execution(* akka.actor.ActorSelection$+.apply(..))
  {
    ActorRef anchor = selection.anchor();
    if (anchor.atmos$traceable()) {
      ActorSystemTracer tracer = anchor.atmos$tracer();
      String path = tracer.actor().selectionPath(selection.path());
      boolean traceable = tracer.actor().traceable(path);
      if (traceable) {
        ActorSelectionInfo info = tracer.actor().selectionInfo(anchor.atmos$info(), path);
        selection.atmos$tracer(tracer);
        selection.atmos$traceable(true);
        selection.atmos$info(info);
      }
    }
  }

  // actor selection message send tracing

  Object around(ActorSelection selection, Object message, ActorRef sender):
    execution(* akka.actor.ActorSelection+.tell(..)) &&
    this(selection) &&
    args(message, sender)
  {
    ActorSystemTracer tracer = selection.atmos$tracer();

    if (disabled(tracer) || !selection.atmos$traceable()) return proceed(selection, message, sender);

    ActorInfo senderInfo = (sender != null && sender.atmos$traceable()) ? sender.atmos$info() : null;
    TraceContext context = tracer.actor().selectionTold(selection.atmos$info(), message, senderInfo);
    tracer.trace().local().start(context);
    Object result = proceed(selection, message, sender);
    tracer.trace().local().end();
    return result;
  }

  // actor selection ask pattern tracing

  Future<Object> around(ActorSelection selection, Object message, Timeout timeout):
    execution(* akka.pattern.AskableActorSelection$.ask$extension(..)) &&
    args(selection, message, timeout)
  {
    ActorSystemTracer tracer = selection.atmos$tracer();

    if (disabled(tracer)) return proceed(selection, message, timeout);

    TraceContext context = TraceContext.EmptyTrace();

    if (selection.atmos$traceable()) {
      context = tracer.actor().selectionAsked(selection.atmos$info(), message);
    }

    tracer.trace().local().start(context);
    Future<Object> future = proceed(selection, message, timeout);
    tracer.trace().local().end();
    return future;
  }

}
