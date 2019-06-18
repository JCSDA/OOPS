/*
 * (C) Copyright 2009-2016 ECMWF.
 * 
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0. 
 * In applying this licence, ECMWF does not waive the privileges and immunities 
 * granted to it by virtue of its status as an intergovernmental organisation nor
 * does it submit to any jurisdiction.
 */

#ifndef TEST_INTERFACE_OBSERVATIONSPACE_H_
#define TEST_INTERFACE_OBSERVATIONSPACE_H_

#include <string>
#include <vector>

#define ECKIT_TESTING_SELF_REGISTER_CASES 0

#include <boost/noncopyable.hpp>

#include "eckit/config/LocalConfiguration.h"
#include "eckit/testing/Test.h"
#include "oops/interface/ObservationSpace.h"
#include "oops/runs/Test.h"
#include "test/interface/ObsTestsFixture.h"
#include "test/TestEnvironment.h"

namespace test {

// -----------------------------------------------------------------------------

template <typename MODEL> void testConstructor() {
  typedef ObsTestsFixture<MODEL> Test_;

  for (std::size_t jj = 0; jj < Test_::obspace().size(); ++jj) {
    EXPECT(Test_::obspace()[jj].windowStart() == Test_::tbgn());
    EXPECT(Test_::obspace()[jj].windowEnd() ==   Test_::tend());
  }
}

// -----------------------------------------------------------------------------

template <typename MODEL> class ObservationSpace : public oops::Test {
 public:
  ObservationSpace() {}
  virtual ~ObservationSpace() {}
 private:
  std::string testid() const {return "test::ObservationSpace<" + MODEL::name() + ">";}

  void register_tests() const {
    std::vector<eckit::testing::Test>& ts = eckit::testing::specification();

    ts.emplace_back(CASE("interface/ObservationSpace/testConstructor")
      { testConstructor<MODEL>(); });
  }
};

// -----------------------------------------------------------------------------

}  // namespace test

#endif  // TEST_INTERFACE_OBSERVATIONSPACE_H_
