//
//  DelayedImmutable.swift
//  ProbabilisticDebugger-UI
//
//  Created by Alex Hoppen on 09.04.20.
//  Copyright © 2020 Alex Hoppen. All rights reserved.
//

@propertyWrapper
struct DelayedImmutable<Value> {
  private var _value: Value?

  init() {
    self._value = nil
  }
  
  var wrappedValue: Value {
    get {
      guard let value = _value else {
        fatalError("property accessed before being initialized")
      }
      return value
    }

    // Perform an initialization, trapping if the
    // value is already initialized.
    set {
      if _value != nil {
        fatalError("property initialized twice")
      }
      _value = newValue
    }
  }
}
