/*
 * (C) Copyright 2009-2016 ECMWF.
 * 
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0. 
 * In applying this licence, ECMWF does not waive the privileges and immunities 
 * granted to it by virtue of its status as an intergovernmental organisation nor
 * does it submit to any jurisdiction.
 */

#ifndef OOPS_INTERFACE_OBSERVATIONSPACE_H_
#define OOPS_INTERFACE_OBSERVATIONSPACE_H_

#include <ostream>
#include <string>

#include <boost/shared_ptr.hpp>

#include "oops/interface/Locations.h"
#include "oops/util/Logger.h"
#include "oops/util/ObjectCounter.h"
#include "oops/util/Printable.h"
#include "oops/util/Timer.h"

namespace eckit {
  class Configuration;
}

namespace util {
  class DateTime;
}

namespace oops {
  template <typename T> class ObsVector;

// -----------------------------------------------------------------------------

template <typename MODEL>
class ObservationSpace : public util::Printable,
                         private boost::noncopyable,
                         private util::ObjectCounter<ObservationSpace<MODEL> > {
  typedef Locations<MODEL>          Locations_;
  typedef typename MODEL::ObsSpace  ObsSpace_;
  typedef ObsVector<MODEL>          ObsVector_;

 public:
  static const std::string classname() {return "oops::ObservationSpace";}

  ObservationSpace(const eckit::Configuration &,
                   const util::DateTime &, const util::DateTime &);
  ~ObservationSpace();

/// Interfacing
  ObsSpace_ & observationspace() const {return *obsdb_;}

/// Assimilation window
  const util::DateTime & windowStart() const {return obsdb_->windowStart();}
  const util::DateTime & windowEnd() const {return obsdb_->windowEnd();}
  const eckit::Configuration & config() const {return obsdb_->config();}

// Other
  void generateDistribution(const eckit::Configuration &);
  void printJo(const ObsVector_ &, const ObsVector_ &) const;

 private:
  void print(std::ostream &) const;
  boost::shared_ptr<ObsSpace_> obsdb_;
};

// -----------------------------------------------------------------------------

template <typename MODEL>
ObservationSpace<MODEL>::ObservationSpace(const eckit::Configuration & conf,
                                          const util::DateTime & bgn,
                                          const util::DateTime & end) : obsdb_() {
  Log::trace() << "ObservationSpace<MODEL>::ObservationSpace starting" << std::endl;
  util::Timer timer(classname(), "ObservationSpace");
  obsdb_.reset(new ObsSpace_(conf, bgn, end));
  if (conf.has("Generate")) {
    const eckit::LocalConfiguration gconf(conf, "Generate");
    obsdb_->generateDistribution(gconf);
  }
  Log::trace() << "ObservationSpace<MODEL>::ObservationSpace done" << std::endl;
}

// -----------------------------------------------------------------------------

template <typename MODEL>
ObservationSpace<MODEL>::~ObservationSpace() {
  Log::trace() << "ObservationSpace<MODEL>::~ObservationSpace" << std::endl;
}

// -----------------------------------------------------------------------------

template <typename MODEL>
void ObservationSpace<MODEL>::print(std::ostream & os) const {
  Log::trace() << "ObservationSpace<MODEL>::print starting" << std::endl;
  util::Timer timer(classname(), "print");
  os << *obsdb_;
  Log::trace() << "ObservationSpace<MODEL>::print done" << std::endl;
}

// -----------------------------------------------------------------------------

template <typename MODEL>
void ObservationSpace<MODEL>::generateDistribution(const eckit::Configuration & conf) {
  Log::trace() << "ObservationSpace<MODEL>::generateDistribution starting" << std::endl;
  util::Timer timer(classname(), "generateDistribution");
  obsdb_->generateDistribution(conf);
  Log::trace() << "ObservationSpace<MODEL>::generateDistribution done" << std::endl;
}

// -----------------------------------------------------------------------------

template <typename MODEL>
void ObservationSpace<MODEL>::printJo(const ObsVector_ & dy, const ObsVector_ & grad) const {
  Log::trace() << "ObservationSpace<MODEL>::printJo starting" << std::endl;
  util::Timer timer(classname(), "printJo");
  obsdb_->printJo(dy.obsvector(), grad.obsvector());
  Log::trace() << "ObservationSpace<MODEL>::printJo done" << std::endl;
}

// -----------------------------------------------------------------------------

}  // namespace oops

#endif  // OOPS_INTERFACE_OBSERVATIONSPACE_H_
