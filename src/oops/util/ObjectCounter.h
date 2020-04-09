/*
 * (C) Copyright 2009-2016 ECMWF.
 * 
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0. 
 * In applying this licence, ECMWF does not waive the privileges and immunities 
 * granted to it by virtue of its status as an intergovernmental organisation nor
 * does it submit to any jurisdiction.
 */

#ifndef OOPS_UTIL_OBJECTCOUNTER_H_
#define OOPS_UTIL_OBJECTCOUNTER_H_

#include <memory>

#include "oops/util/ObjectCountHelper.h"

namespace util {

// -----------------------------------------------------------------------------

template<typename T>
class ObjectCounter {
 public:
  ObjectCounter(): count_(ObjectCountHelper::create(T::classname()))
    {count_->oneMore();}

  ObjectCounter(const ObjectCounter & other) : count_(other.count_)
    {count_->oneMore();}

  ~ObjectCounter()
    {count_->oneLess();}

 private:
  std::shared_ptr<ObjectCountHelper> count_;
};

// -----------------------------------------------------------------------------

}  // namespace util

#endif  // OOPS_UTIL_OBJECTCOUNTER_H_
