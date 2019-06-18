/*
 * (C) Copyright 2009-2016 ECMWF.
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 * In applying this licence, ECMWF does not waive the privileges and immunities
 * granted to it by virtue of its status as an intergovernmental organisation nor
 * does it submit to any jurisdiction.
 */

#ifndef QG_MODEL_OBSOPERATORQG_H_
#define QG_MODEL_OBSOPERATORQG_H_

#include <memory>
#include <string>

#include <boost/noncopyable.hpp>

#include "oops/base/Variables.h"
#include "oops/util/Printable.h"

// Forward declarations
namespace eckit {
  class Configuration;
}

namespace util {
  class DateTime;
}

namespace qg {
  class GomQG;
  class LocationsQG;
  class ObsBias;
  class ObsOpBaseQG;
  class ObsSpaceQG;
  class ObsVecQG;

// -----------------------------------------------------------------------------

class ObsOperatorQG : public util::Printable,
                      private boost::noncopyable {
 public:
  ObsOperatorQG(const ObsSpaceQG &, const eckit::Configuration &);
  ~ObsOperatorQG();

/// Obs Operator
  void simulateObs(const GomQG &, ObsVecQG &, const ObsBias &) const;

/// Other
  const oops::Variables & variables() const;  // Required input variables from Model
  LocationsQG * locations(const util::DateTime &, const util::DateTime &) const;

 private:
  void print(std::ostream &) const;
  std::unique_ptr<ObsOpBaseQG> oper_;
};

// -----------------------------------------------------------------------------

}  // namespace qg

#endif  // QG_MODEL_OBSOPERATORQG_H_
