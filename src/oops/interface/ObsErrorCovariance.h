/*
 * (C) Copyright 2009-2016 ECMWF.
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 * In applying this licence, ECMWF does not waive the privileges and immunities
 * granted to it by virtue of its status as an intergovernmental organisation nor
 * does it submit to any jurisdiction.
 */

#ifndef OOPS_INTERFACE_OBSERRORCOVARIANCE_H_
#define OOPS_INTERFACE_OBSERRORCOVARIANCE_H_

#include <memory>
#include <string>

#include "eckit/system/ResourceUsage.h"

#include "oops/base/ObsErrorBase.h"
#include "oops/interface/ObsSpace.h"
#include "oops/interface/ObsVector.h"

namespace eckit {
  class Configuration;
}

namespace oops {

// -----------------------------------------------------------------------------
/// Observation error covariance matrix
/*!
 *  This class provides the operations associated with the observation
 *  error covariance matrix. It wraps model specific observation error covariances.
 */

template <typename OBS, typename OBSERR>
class ObsErrorCovariance : public oops::ObsErrorBase<OBS> {
  typedef ObsSpace<OBS>            ObsSpace_;
  typedef ObsVector<OBS>           ObsVector_;

 public:
  static const std::string classname() {return "oops::ObsErrorCovariance";}

  ObsErrorCovariance(const eckit::Configuration &, const ObsSpace_ &, const Variables &);
  ~ObsErrorCovariance();

/// Multiply a Departure by \f$R\f$ and \f$R^{-1}\f$
  void multiply(ObsVector_ &) const;
  void inverseMultiply(ObsVector_ &) const;

/// Generate random perturbation
  void randomize(ObsVector_ &) const;

/// Get mean error for Jo table
  double getRMSE() const;

 private:
  void print(std::ostream &) const;
  std::unique_ptr<OBSERR> covar_;
};

// ====================================================================================

template <typename OBS, typename OBSERR>
ObsErrorCovariance<OBS, OBSERR>::ObsErrorCovariance(const eckit::Configuration & conf,
                                                      const ObsSpace_ & obsdb,
                                                      const Variables & obsvar) : covar_() {
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::ObsErrorCovariance starting" << std::endl;
  util::Timer timer(classname(), "ObsErrorCovariance");
  size_t init = eckit::system::ResourceUsage().maxResidentSetSize();
  covar_.reset(new OBSERR(conf, obsdb, obsvar));
  size_t current = eckit::system::ResourceUsage().maxResidentSetSize();
  this->setObjectSize(current - init);
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::ObsErrorCovariance done" << std::endl;
}

// -----------------------------------------------------------------------------

template <typename OBS, typename OBSERR>
ObsErrorCovariance<OBS, OBSERR>::~ObsErrorCovariance() {
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::~ObsErrorCovariance starting" << std::endl;
  util::Timer timer(classname(), "~ObsErrorCovariance");
  covar_.reset();
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::~ObsErrorCovariance done" << std::endl;
}

// -----------------------------------------------------------------------------

template <typename OBS, typename OBSERR>
void ObsErrorCovariance<OBS, OBSERR>::multiply(ObsVector_ & dy) const {
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::multiply starting" << std::endl;
  util::Timer timer(classname(), "multiply");
  covar_->multiply(dy.obsvector());
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::multiply done" << std::endl;
}

// -----------------------------------------------------------------------------

template <typename OBS, typename OBSERR>
void ObsErrorCovariance<OBS, OBSERR>::inverseMultiply(ObsVector_ & dy) const {
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::inverseMultiply starting" << std::endl;
  util::Timer timer(classname(), "inverseMultiply");
  covar_->inverseMultiply(dy.obsvector());
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::inverseMultiply done" << std::endl;
}

// -----------------------------------------------------------------------------

template <typename OBS, typename OBSERR>
void ObsErrorCovariance<OBS, OBSERR>::randomize(ObsVector_ & dy) const {
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::randomize starting" << std::endl;
  util::Timer timer(classname(), "randomize");
  covar_->randomize(dy.obsvector());
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::randomize done" << std::endl;
}

// -----------------------------------------------------------------------------

template <typename OBS, typename OBSERR>
double ObsErrorCovariance<OBS, OBSERR>::getRMSE() const {
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::getRMSE starting" << std::endl;
  util::Timer timer(classname(), "getRMSE");
  double zz = covar_->getRMSE();
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::getRMSE done" << std::endl;
  return zz;
}

// -----------------------------------------------------------------------------

template<typename OBS, typename OBSERR>
void ObsErrorCovariance<OBS, OBSERR>::print(std::ostream & os) const {
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::print starting" << std::endl;
  util::Timer timer(classname(), "print");
  os << *covar_;
  Log::trace() << "ObsErrorCovariance<OBS, OBSERR>::print done" << std::endl;
}

// -----------------------------------------------------------------------------

}  // namespace oops

#endif  // OOPS_INTERFACE_OBSERRORCOVARIANCE_H_
