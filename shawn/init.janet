(import shawn/event :as event)

(defn- _process-stream [store]
  (put store :processing true)
  (def stream (store :_stream))
  (defn return [what] (array/insert stream 0 what))
  (while (not (empty? stream))
    (match (array/pop stream)
      (e (event/valid? e)) (:transact store e)
      (fiber (fiber? fiber) (= (fiber/status fiber) :alive)) (return fiber)
      (fiber (fiber? fiber) (or (= (fiber/status fiber) :pending)
                                (= (fiber/status fiber) :new)))
      (do (return fiber) (:transact store (resume fiber)))
      [id (thread (= (type thread) :core/thread))]
      (match (protect (thread/receive (store :tick)))
        [true [(msg (= msg :fin)) tid]]
        (if (= id tid)
          (:close thread)
          (let [ti (find-index |(= (first $) tid) (return [id thread]))
                t (get-in stream [ti 1])]
            (:close t)
            (array/remove stream ti)))
        [true evt] (do (return [id thread]) (:transact store (event/make evt)))
        [false _] (return [id thread]))))
  (put store :processing false))

(defn- _notify [store]
  (defer (put store :_old-state nil)
    (unless (or (empty? (store :_observers))
                (deep= (store :_old-state) (store :state)))
      (each o (store :_observers)
        (o (store :_old-state) (store :state))))))

(defn transact
  ```
  Tansacts Event into Store. Has two parameters:

  * store: Store to which we are transacting
  * event: Event we are transacting. Throws when the Event is invalid

  This functions is called when you call :transact method on Store
  ```
  [store event]
  (assert (event/valid? event) (string "Only Events are transactable. Got: " event))
  (def {:state state :_stream stream} store)
  (put store :_old-state (table/clone state))
  (:update event state)
  (:_notify store)
  (match (:watch event state stream)
    (arr (indexed? arr) (all event/valid? arr))
    (array/concat stream (reverse arr))
    (eorf (or (event/valid? eorf) (fiber? eorf)))
    (array/push stream eorf)
    (thread (= (type thread) :core/thread))
    (let [tid (string thread)]
      (:send thread tid)
      (array/push stream [tid thread]))
    bad (error (string "Only Event, Array of Events, Fiber and Thread are watchable. Got:" (type bad))))
  (:effect event state stream)
  (unless (store :processing) (:_process-stream store)))

(defn observe
  ```
  Adds observer function to a store. Has two parameters:

  * store: Store to which observer is added
  * observer: observer function

  Observer functions are called everytime state changes with two parameters:

  * old-state: state before the change
  * new-state: state after the change

  This function is called when you call :observe method on Store
  ```
  [store observer]
  (array/push (store :_observers) observer))

(def Store
  ```
  Store prototype. It has two public methods:

  * (:transact store event): transacts given Event
  * (:observe store obserer): adds observer to the Store
  ```
  @{:tick (/ 60)
    :transact transact
    :observe observe
    :_old-state nil
    :_stream @[]
    :_observers @[]
    :_process-stream _process-stream
    :_notify _notify})

(defn init-store
  ```
  Factory function for creating new Store with two optional parameters:

  * state: initial state for the Store. Default @{}. Throws when state is not table
  * opts: pairs with options for the Store, they are merged after setting Store prototype.

  Throws when opts do not have even count.
  ```
  [&opt state & opts]
  (default state @{})
  (assert (table? state) "State must be table")
  (assert (even? (length opts)) "Options must be even count pairs of key and value")
  (-> @{:state state} (table/setproto Store) (merge-into (table ;opts))))
