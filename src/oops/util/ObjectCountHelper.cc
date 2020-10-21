/*
 * (C) Copyright 2009-2016 ECMWF.
 * 
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0. 
 * In applying this licence, ECMWF does not waive the privileges and immunities 
 * granted to it by virtue of its status as an intergovernmental organisation nor
 * does it submit to any jurisdiction.
 */

#include "oops/util/ObjectCountHelper.h"

#include <algorithm>
#include <iomanip>
#include <string>

#include "eckit/exception/Exceptions.h"
#include "oops/util/Logger.h"

namespace util {

// -----------------------------------------------------------------------------

std::map<std::string, std::shared_ptr<ObjectCountHelper> > * ObjectCountHelper::counters_ = 0;

// -----------------------------------------------------------------------------

void ObjectCountHelper::start() {
  ASSERT(!counters_);
  counters_ = new std::map < std::string, std::shared_ptr<ObjectCountHelper> >();
  ASSERT(counters_);
  oops::Log::stats() << "ObjectCountHelper started." << std::endl;
}

// -----------------------------------------------------------------------------

void ObjectCountHelper::stop() {
  ASSERT(counters_);
  typedef std::map<std::string, std::shared_ptr<ObjectCountHelper> >::iterator it;
  oops::Log::stats() << " " << std::endl;
  oops::Log::stats() << "----------------------------------------------------------------------"
                     << std::endl;
  oops::Log::stats() << "--------------------------- Object counts ----------------------------"
                     << std::endl;
  oops::Log::stats() << "----------------------------------------------------------------------"
                     << std::endl;
  for (it jc = counters_->begin(); jc != counters_->end(); ++jc) {
    oops::Log::stats() << std::setw(32) << std::left << jc->first
                       << ": " << *(jc->second) << std::endl;
  }
  oops::Log::stats() << "----------------------------- Object counts --------------------------"
                     << std::endl;
  counters_->clear();
}

// -----------------------------------------------------------------------------

std::shared_ptr<ObjectCountHelper> ObjectCountHelper::create(const std::string & cname) {
  std::shared_ptr<ObjectCountHelper> pcount;
  typedef std::map<std::string, std::shared_ptr<ObjectCountHelper> >::iterator it;
  it jj = counters_->find(cname);
  if (jj == counters_->end()) {
    pcount.reset(new ObjectCountHelper(cname));
    (*counters_)[cname] = pcount;
  } else {
    pcount = jj->second;
  }
  return pcount;
}

// -----------------------------------------------------------------------------

ObjectCountHelper::ObjectCountHelper(const std::string & cname)
    : current_(0), created_(0), max_(0) {}

// -----------------------------------------------------------------------------

ObjectCountHelper::~ObjectCountHelper() {}

// -----------------------------------------------------------------------------

void ObjectCountHelper::oneMore() {
  ++current_;
  ++created_;
  max_ = std::max(max_, current_);
}

// -----------------------------------------------------------------------------

void ObjectCountHelper::oneLess() {
  --current_;
}

// -----------------------------------------------------------------------------

void ObjectCountHelper::print(std::ostream & out) const {
  out << "simultaneous = " << std::setw(5) << std::right << max_
      << ", total = " << std::setw(6) << std::right << created_;
  if (current_ > 0) out << ", not destructed = " << std::setw(5) << std::right << current_;
}

// -----------------------------------------------------------------------------

}  // namespace util
