/*
 * (C) Copyright 2020-2020 UCAR
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#ifndef LORENZ95_BACKGROUNDCHECK_H_
#define LORENZ95_BACKGROUNDCHECK_H_

#include <memory>
#include <ostream>

#include "oops/base/ObsFilterParametersBase.h"
#include "oops/base/Variables.h"
#include "oops/util/parameters/OptionalParameter.h"
#include "oops/util/parameters/RequiredParameter.h"
#include "oops/util/Printable.h"

namespace lorenz95 {
  class GomL95;
  template <typename DATATYPE> class ObsData1D;
  class ObsTable;
  class ObsDiags1D;
  class ObsVec1D;

/// Parameters for L95 BackgroundCheck
/// background check: all obs for which {|y-H(x)| < threshold} pass QC
class BackgroundCheckParameters : public oops::ObsFilterParametersBase {
  OOPS_CONCRETE_PARAMETERS(BackgroundCheckParameters, ObsFilterParametersBase)

 public:
  /// threshold for background check
  oops::RequiredParameter<double> threshold{"threshold", this};

  /// optional inflation factor: if this parameter is present, obs error stddev
  /// for obs that don't pass the check is multiplied by the specified factor.
  /// Otherwise, obs that don't pass the check are rejected.
  oops::OptionalParameter<double> inflation{"inflate obs error", this};
};

/// Simple background check: all obs for which {|y-H(x)| < threshold} pass QC
class BackgroundCheck : public util::Printable {
 public:
  typedef BackgroundCheckParameters Parameters_;

  BackgroundCheck(const ObsTable &, const Parameters_ &,
                  std::shared_ptr<ObsData1D<int> >, std::shared_ptr<ObsData1D<float> >);

  void preProcess() const {}
  void priorFilter(const GomL95 &) const {}
  void postFilter(const ObsVec1D &, const ObsDiags1D &) const;

  oops::Variables requiredVars() const {return novars_;}
  oops::Variables requiredHdiagnostics() const {return novars_;}

 private:
  void print(std::ostream & os) const;

  const ObsTable & obsdb_;
  Parameters_ options_;
  std::shared_ptr<ObsData1D<int> > qcflags_;   // QC flags
  std::shared_ptr<ObsData1D<float> > obserr_;  // obs error stddev
  const oops::Variables novars_;
};

}  // namespace lorenz95

#endif  // LORENZ95_BACKGROUNDCHECK_H_
