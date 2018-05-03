!----------------------------------------------------------------------
! Module: type_obsop
!> Purpose: observation operator data derived type
!> <br>
!> Author: Benjamin Menetrier
!> <br>
!> Licensing: this code is distributed under the CeCILL-C license
!> <br>
!> Copyright © 2015-... UCAR, CERFACS and METEO-FRANCE
!----------------------------------------------------------------------
module type_obsop

use tools_const, only: pi,rad2deg,reqkm
use tools_display, only: msgerror
use tools_func, only: sphere_dist
use tools_kinds, only: kind_real
use tools_missing, only: msi,msr,isnotmsi,isnotmsr
use tools_qsort, only: qsort
use type_com, only: com_type
use type_geom, only: geom_type
use type_linop, only: linop_type
use type_mpl, only: mpl
use type_nam, only: nam_type
use type_rng, only: rng

implicit none

! Observation operator data derived type
type obsop_type
   ! Observations
   integer :: nobs                          !< Number of observations
   real(kind_real),allocatable :: lonobs(:) !< Observations longitudes
   real(kind_real),allocatable :: latobs(:) !< Observations latitudes

   ! Interpolation data
   type(linop_type) :: hfull                !< Full interpolation data

   ! MPI distribution
   integer,allocatable :: obs_to_proc(:)    !< Observation to processor
   integer,allocatable :: obs_to_obsa(:)    !< Observation to local observation
   integer,allocatable :: obsa_to_obs(:)    !< Local observation to observation
   integer,allocatable :: proc_to_nobsa(:)  !< Processor to local number of observations
   integer,allocatable :: c0b_to_c0(:)      !< Subset Sc0, halo B to global
   integer,allocatable :: c0_to_c0b(:)      !< Subset Sc0, global to halo B
   integer,allocatable :: c0a_to_c0b(:)     !< Subset Sc0, halo A to halo B

   ! Required data to apply an observation operator

   ! Number of points
   integer :: nc0b                          !< Halo B size

   ! Number of observations
   integer :: nobsa                         !< Local number of observations

   ! Interpolation data
   type(linop_type) :: h                    !< Interpolation data

   ! Communication data
   type(com_type) :: com                    !< Communication data
contains
   procedure :: generate => obsop_generate
   procedure :: from => obsop_from
   procedure :: run_obsop => obsop_run_obsop
   procedure :: parameters => obsop_parameters
   procedure :: apply => obsop_apply
   procedure :: apply_ad => obsop_apply_ad
   procedure :: test_adjoint => obsop_test_adjoint
   procedure :: test_accuracy => obsop_test_accuracy
end type obsop_type

private
public :: obsop_type

contains

!----------------------------------------------------------------------
! Subroutine: obsop_generate
!> Purpose: generate observations locations
!----------------------------------------------------------------------
subroutine obsop_generate(obsop,nam,geom)

implicit none

! Passed variables
class(obsop_type),intent(inout) :: obsop !< Observation operator data
type(nam_type),intent(in) :: nam         !< Namelist
type(geom_type),intent(in) :: geom       !< Geometry

! Local variables
integer :: info,iobs
real(kind_real) :: lat,lon
logical :: readobs
character(len=1024) :: filename

! Define number of observations
filename = trim(nam%datadir)//'/'//trim(nam%prefix)//'_obs_in.dat'
inquire(file=trim(filename),exist=readobs)
if (readobs) then
   ! Read observation network
   obsop%nobs = 0
   open(unit=100,file=trim(filename),status='old')
   do
      read(100,*,iostat=info) lat,lon
      if (info/=0) exit
      obsop%nobs = obsop%nobs+1
   end do
   close(unit=100)
   obsop%nobs = min(obsop%nobs,nam%nobs)
   if (obsop%nobs<1) call msgerror('no observation in the file provided')
else
   ! Generate random observation network
   obsop%nobs = nam%nobs
end if

! Allocation
allocate(obsop%lonobs(obsop%nobs))
allocate(obsop%latobs(obsop%nobs))

! Get observation locations
if (mpl%main) then
   if (readobs) then
      ! Read observation network
      open(unit=100,file=trim(nam%datadir)//'/'//trim(nam%prefix)//'_obs_in.dat',status='old')
      iobs = 0
      do while (iobs<obsop%nobs)
         read(100,*) lat,lon
         iobs = iobs+1
         obsop%lonobs(iobs) = lon
         obsop%latobs(iobs) = lat
      end do
      close(unit=100)
   else
      ! Generate random observation network
      if (abs(maxval(geom%area)-4.0*pi)<1.0e-1) then
         ! Limited-area domain
         call rng%rand_real(minval(geom%lon),maxval(geom%lon),obsop%lonobs)
         call rng%rand_real(minval(geom%lat),maxval(geom%lat),obsop%latobs)
      else
         ! Global domain
         call rng%rand_real(-pi,pi,obsop%lonobs)
         call rng%rand_real(-1.0_kind_real,1.0_kind_real,obsop%latobs)
         obsop%latobs = 0.5*pi-acos(obsop%latobs)
      end if
   end if
end if

! Broadcast data
call mpl%bcast(obsop%lonobs)
call mpl%bcast(obsop%latobs)

! Print results
write(mpl%unit,'(a7,a,i8)') '','Number of observations: ',obsop%nobs
call flush(mpl%unit)

end subroutine obsop_generate

!----------------------------------------------------------------------
! Subroutine: obsop_from
!> Purpose: copy observation operator data
!----------------------------------------------------------------------
subroutine obsop_from(obsop,nobs,lonobs,latobs)

implicit none

! Passed variables
class(obsop_type),intent(inout) :: obsop   !< Observation operator data
integer,intent(in) :: nobs                 !< Number of observations
real(kind_real),intent(in) :: lonobs(nobs) !< Observations longitudes
real(kind_real),intent(in) :: latobs(nobs) !< Observations latitudes

! Get size
obsop%nobs = nobs

! Allocation
allocate(obsop%lonobs(obsop%nobs))
allocate(obsop%latobs(obsop%nobs))

! Copy
obsop%lonobs = lonobs
obsop%latobs = latobs

end subroutine obsop_from

!----------------------------------------------------------------------
! Subroutine: obsop_run_obsop
!> Purpose: observation operator driver
!----------------------------------------------------------------------
subroutine obsop_run_obsop(obsop,nam,geom)

implicit none

! Passed variables
class(obsop_type),intent(inout) :: obsop !< Observation operator data
type(nam_type),intent(in) :: nam         !< Namelist
type(geom_type),intent(in) :: geom       !< Geometry

! Compute observation operator parameters
write(mpl%unit,'(a)') '-------------------------------------------------------------------'
write(mpl%unit,'(a)') '--- Compute observation operator parameters'
call flush(mpl%unit)
call obsop%parameters(nam,geom)

if (nam%check_adjoints) then
   ! Test adjoints
   write(mpl%unit,'(a)') '-------------------------------------------------------------------'
   write(mpl%unit,'(a)') '--- Test observation operator adjoint'
   call flush(mpl%unit)
   call obsop%test_adjoint(geom)
end if

! Test precision
write(mpl%unit,'(a)') '-------------------------------------------------------------------'
write(mpl%unit,'(a)') '--- Test observation operator precision'
call flush(mpl%unit)
call obsop%test_accuracy(geom)

end subroutine obsop_run_obsop

!----------------------------------------------------------------------
! Subroutine: obsop_parameters
!> Purpose: compute observation operator interpolation parameters
!----------------------------------------------------------------------
subroutine obsop_parameters(obsop,nam,geom)

implicit none

! Passed variables
class(obsop_type),intent(inout) :: obsop !< Observation operator data
type(nam_type),intent(in) :: nam         !< Namelist
type(geom_type),intent(in) :: geom       !< Geometry

! Local variables
integer :: offset,iobs,jobs,iobsa,iproc,nobsa,i_s,ic0,ic0b,i,ic0a,nc0a,nc0b,delta,nres,ind(1),lunit
integer :: imin(1),imax(1),nmoves,imoves
integer,allocatable :: nop(:),iop(:),srcproc(:,:),srcic0(:,:),order(:),nobs_to_move(:),nobs_to_move_tmp(:),obs_moved(:,:)
integer,allocatable :: c0_to_c0a(:),c0a_to_c0(:),c0b_to_c0(:),c0a_to_c0b(:)
real(kind_real) :: N_max,C_max
real(kind_real),allocatable :: proc_to_lonobs(:),proc_to_latobs(:),lonobs(:),latobs(:),list(:)
logical :: global
logical,allocatable :: maskobs(:),lcheck_nc0b(:)
type(com_type) :: com(mpl%nproc)

! Allocation
allocate(obsop%proc_to_nobsa(mpl%nproc))

! Find out if obs are global or local
call mpl%allgather(1,(/obsop%nobs/),obsop%proc_to_nobsa)
global = all(obsop%proc_to_nobsa==obsop%proc_to_nobsa(mpl%ioproc))
if (global) then
   ! Allocation
   allocate(proc_to_lonobs(mpl%nproc))
   allocate(proc_to_latobs(mpl%nproc))

   iobs = 1
   do while (global.and.(iobs<=obsop%nobs))
      ! Gather
      call mpl%allgather(1,(/obsop%lonobs(iobs)/),proc_to_lonobs)
      call mpl%allgather(1,(/obsop%latobs(iobs)/),proc_to_latobs)

      ! Check
      global = all(.not.abs(proc_to_lonobs-proc_to_lonobs(mpl%ioproc))<0.0) &
             & .and.all(.not.abs(proc_to_latobs-proc_to_latobs(mpl%ioproc))<0.0)

      ! Update
      iobs = iobs+1
   end do
end if

if (global) then
   ! Allocation
   allocate(lonobs(obsop%nobs))
   allocate(latobs(obsop%nobs))

   ! Copy coordinates
   lonobs = obsop%lonobs
   latobs = obsop%latobs
else
   ! Get global number of observations
   obsop%nobsa = obsop%nobs
   obsop%nobs = sum(obsop%proc_to_nobsa)

   ! Allocation
   allocate(lonobs(obsop%nobs))
   allocate(latobs(obsop%nobs))

   ! Get observations coordinates
   if (mpl%main) then
      offset = 0
      do iproc=1,mpl%nproc
         if (obsop%proc_to_nobsa(iproc)>0) then
            if (iproc==mpl%ioproc) then
               ! Copy data
               lonobs(offset+1:offset+obsop%proc_to_nobsa(iproc)) = obsop%lonobs
               latobs(offset+1:offset+obsop%proc_to_nobsa(iproc)) = obsop%latobs
            else
               ! Receive data on ioproc
               call mpl%recv(obsop%proc_to_nobsa(iproc),lonobs(offset+1:offset+obsop%proc_to_nobsa(iproc)),iproc,mpl%tag)
               call mpl%recv(obsop%proc_to_nobsa(iproc),latobs(offset+1:offset+obsop%proc_to_nobsa(iproc)),iproc,mpl%tag+1)
            end if
         end if

         ! Update offset
         offset = offset+obsop%proc_to_nobsa(iproc)
      end do
   else
      if (obsop%nobsa>0) then
         ! Send data to ioproc
         call mpl%send(obsop%nobsa,obsop%lonobs,mpl%ioproc,mpl%tag)
         call mpl%send(obsop%nobsa,obsop%latobs,mpl%ioproc,mpl%tag+1)
      end if
   end if
   mpl%tag = mpl%tag+2

   ! Broadcast data
   call mpl%bcast(lonobs)
   call mpl%bcast(latobs)
end if

! Allocation
allocate(maskobs(obsop%nobs))
allocate(nop(obsop%nobs))
allocate(iop(obsop%nobs))
allocate(obsop%obs_to_proc(obsop%nobs))
allocate(obsop%obs_to_obsa(obsop%nobs))

! Compute interpolation
obsop%hfull%prefix = 'o'
write(mpl%unit,'(a7,a)') '','Single level:'
call flush(mpl%unit)
maskobs = .true.
call obsop%hfull%interp(geom%mesh,geom%ctree,geom%nc0,any(geom%mask,dim=2),obsop%nobs,lonobs,latobs,maskobs,nam%obsop_interp)

! Count interpolation points
nop = 0
do i_s=1,obsop%hfull%n_s
   iobs = obsop%hfull%row(i_s)
   nop(iobs) = nop(iobs)+1
end do

! Allocation
allocate(srcproc(maxval(nop),obsop%nobs))
allocate(srcic0(maxval(nop),obsop%nobs))

! Find grid points origin
iop = 0
call msi(srcproc)
call msi(srcic0)
do i_s=1,obsop%hfull%n_s
   ic0 = obsop%hfull%col(i_s)
   iproc = geom%c0_to_proc(ic0)
   iobs = obsop%hfull%row(i_s)
   iop(iobs) = iop(iobs)+1
   srcproc(iop(iobs),iobs) = iproc
   srcic0(iop(iobs),iobs) = ic0
end do

if (global) then
   ! Generate observation distribution on processors
   select case (trim(nam%obsdis))
   case('random')
      ! Allocation
      allocate(list(obsop%nobs))
      allocate(order(obsop%nobs))

      ! Random repartition
      if (mpl%main) call rng%rand_real(0.0_kind_real,1.0_kind_real,list)
      call mpl%bcast(list)
      call qsort(obsop%nobs,list,order)
      nobsa = obsop%nobs/mpl%nproc
      if (nobsa*mpl%nproc<obsop%nobs) nobsa = nobsa+1
      iproc = 1
      iobsa = 1
      do iobs=1,obsop%nobs
         jobs = order(iobs)
         obsop%obs_to_proc(jobs) = iproc
         iobsa = iobsa+1
         if (iobsa>nobsa) then
            iproc = iproc+1
            iobsa = 1
         end if
      end do

      ! Release memory
      deallocate(list)
      deallocate(order)
   case ('local','adjusted')
      ! Source grid-based repartition
      do iobs=1,obsop%nobs
         ! Set observation proc
         if (isnotmsi(srcproc(2,iobs)).and.(srcproc(2,iobs)==srcproc(3,iobs))) then
            ! Set to second point proc
            obsop%obs_to_proc(iobs) = srcproc(2,iobs)
         else
            ! Set to first point proc
            obsop%obs_to_proc(iobs) = srcproc(1,iobs)
         end if
      end do

      if (trim(nam%obsdis)=='adjusted') then
         ! Allocation
         allocate(nobs_to_move(mpl%nproc))

         ! Proc to nobsa
         obsop%proc_to_nobsa = 0
         do iobs=1,obsop%nobs
            ! Concerned proc
            iproc = obsop%obs_to_proc(iobs)

            ! Number of observations per proc
            obsop%proc_to_nobsa(iproc) = obsop%proc_to_nobsa(iproc)+1
         end do

         ! Target nobsa, nobsa to move
         nres = obsop%nobs
         do iproc=1,mpl%nproc
            delta = obsop%nobs/mpl%nproc
            if (nres>(mpl%nproc-iproc+1)*delta) delta = delta+1
            nobs_to_move(iproc) = delta
            nres = nres-delta
         end do
         nobs_to_move = int(real(obsop%proc_to_nobsa-nobs_to_move,kind_real))
         if (sum(nobs_to_move)>0) then
            ind = maxloc(nobs_to_move)
         elseif (sum(nobs_to_move)<0) then
            ind = minloc(nobs_to_move)
         else
            ind = 1
         end if
         nobs_to_move(ind(1)) = nobs_to_move(ind(1))-sum(nobs_to_move)

         ! Select observations to move
         allocate(nobs_to_move_tmp(mpl%nproc))
         allocate(obs_moved(maxval(abs(nobs_to_move)),mpl%nproc))
         call msi(obs_moved)
         nobs_to_move_tmp = nobs_to_move
         do iobs=1,obsop%nobs
            iproc = obsop%obs_to_proc(iobs)
            if (nobs_to_move_tmp(iproc)>0) then
               ! Move this observation from iproc
               obs_moved(nobs_to_move_tmp(iproc),iproc) = iobs
               nobs_to_move_tmp(iproc) = nobs_to_move_tmp(iproc)-1
            end if
         end do

         ! Select destination proc
         do while (any(nobs_to_move<0))
            imin = minloc(nobs_to_move)
            imax = maxloc(nobs_to_move)
            nmoves = min(nobs_to_move(imax(1)),-nobs_to_move(imin(1)))
            do imoves=1,nmoves
               iobs = obs_moved(nobs_to_move(imax(1)),imax(1))
               call msi(obs_moved(nobs_to_move(imax(1)),imax(1)))
               obsop%obs_to_proc(iobs) = imin(1)
               nobs_to_move(imax(1)) = nobs_to_move(imax(1))-1
               nobs_to_move(imin(1)) = nobs_to_move(imin(1))+1
            end do
         end do

         ! Release memory
         deallocate(nobs_to_move)
      end if
   end select

   ! Local number of observations
   obsop%proc_to_nobsa = 0
   do iobs=1,obsop%nobs
      ! Concerned proc
      iproc = obsop%obs_to_proc(iobs)

      ! Number of observations per proc
      obsop%proc_to_nobsa(iproc) = obsop%proc_to_nobsa(iproc)+1
   end do

   ! Define nobsa
   obsop%nobsa = obsop%proc_to_nobsa(mpl%myproc)
else
   ! Fill obs_to_proc
   iobs = 0
   do iproc=1,mpl%nproc
      do iobsa=1,obsop%proc_to_nobsa(iproc)
         iobs = iobs+1
         obsop%obs_to_proc(iobs) = iproc
      end do
   end do
end if

! Allocation
allocate(obsop%obsa_to_obs(obsop%nobsa))

! Fill obs_to_obsa and obsa_to_obs
obsop%proc_to_nobsa = 0
do iobs=1,obsop%nobs
   ! Concerned proc
   iproc = obsop%obs_to_proc(iobs)

   ! Number of observations per proc
   obsop%proc_to_nobsa(iproc) = obsop%proc_to_nobsa(iproc)+1

   ! Observations local index
   iobsa = obsop%proc_to_nobsa(iproc)
   obsop%obs_to_obsa(iobs) = iobsa
   if (iproc==mpl%myproc) obsop%obsa_to_obs(iobsa) = iobs
end do

! Allocation
allocate(lcheck_nc0b(geom%nc0))

! Count number of local interpolation operations
obsop%h%n_s = 0
do i_s=1,obsop%hfull%n_s
   iobs = obsop%hfull%row(i_s)
   iproc = obsop%obs_to_proc(iobs)
   if (iproc==mpl%myproc) obsop%h%n_s = obsop%h%n_s+1
end do

! Count halo points
lcheck_nc0b = .false.
do ic0a=1,geom%nc0a
   ic0 = geom%c0a_to_c0(ic0a)
   if (geom%c0_to_proc(ic0)==mpl%myproc) lcheck_nc0b(ic0) = .true.
end do
do iobs=1,obsop%nobs
   iproc = obsop%obs_to_proc(iobs)
   if (iproc==mpl%myproc) then
      do i=1,iop(iobs)
         ic0 = srcic0(i,iobs)
         lcheck_nc0b(ic0) = .true.
      end do
   end if
end do
obsop%nc0b = count(lcheck_nc0b)

! Define halo points
allocate(obsop%c0b_to_c0(obsop%nc0b))
allocate(obsop%c0_to_c0b(geom%nc0))
call msi(obsop%c0_to_c0b)
ic0b = 0
do ic0=1,geom%nc0
   if (lcheck_nc0b(ic0)) then
      ic0b = ic0b+1
      obsop%c0b_to_c0(ic0b) = ic0
      obsop%c0_to_c0b(ic0) = ic0b
   end if
end do

! Split interpolation data
obsop%h%prefix = 'o'
obsop%h%n_src = obsop%nc0b
obsop%h%n_dst = obsop%nobsa
call obsop%h%alloc
obsop%h%n_s = 0
do i_s=1,obsop%hfull%n_s
   iobs = obsop%hfull%row(i_s)
   ic0 = obsop%hfull%col(i_s)
   iproc = obsop%obs_to_proc(iobs)
   if (iproc==mpl%myproc) then
      obsop%h%n_s = obsop%h%n_s+1
      obsop%h%row(obsop%h%n_s) = obsop%obs_to_obsa(iobs)
      obsop%h%col(obsop%h%n_s) = obsop%c0_to_c0b(ic0)
      obsop%h%S(obsop%h%n_s) = obsop%hfull%S(i_s)
   end if
end do

! Inter-halo conversions
allocate(obsop%c0a_to_c0b(geom%nc0a))
do ic0a=1,geom%nc0a
   ic0 = geom%c0a_to_c0(ic0a)
   ic0b = obsop%c0_to_c0b(ic0)
   obsop%c0a_to_c0b(ic0a) = ic0b
end do

! Get global distribution of the subgrid on ioproc
if (mpl%main) then
   ! Allocation
   allocate(c0_to_c0a(geom%nc0))

   do iproc=1,mpl%nproc
      if (iproc==mpl%ioproc) then
         ! Copy dimension
         nc0a = geom%nc0a
      else
         ! Receive dimension on ioproc
         call mpl%recv(nc0a,iproc,mpl%tag)
      end if

      ! Allocation
      allocate(c0a_to_c0(nc0a))

      if (iproc==mpl%ioproc) then
         ! Copy data
         c0a_to_c0 = geom%c0a_to_c0
      else
         ! Receive data on ioproc
         call mpl%recv(nc0a,c0a_to_c0,iproc,mpl%tag+1)
      end if

      ! Fill c0_to_c0a
      do ic0a=1,nc0a
         c0_to_c0a(c0a_to_c0(ic0a)) = ic0a
      end do

      ! Release memory
      deallocate(c0a_to_c0)
   end do
else
   ! Send dimensions to ioproc
   call mpl%send(geom%nc0a,mpl%ioproc,mpl%tag)

   ! Send data to ioproc
   call mpl%send(geom%nc0a,geom%c0a_to_c0,mpl%ioproc,mpl%tag+1)
end if
mpl%tag = mpl%tag+2

! Setup communications
if (mpl%main) then
   do iproc=1,mpl%nproc
      ! Communicate dimensions
      if (iproc==mpl%ioproc) then
         ! Copy dimensions
         nc0a = geom%nc0a
         nc0b = obsop%nc0b
      else
         ! Receive dimensions on ioproc
         call mpl%recv(nc0a,iproc,mpl%tag)
         call mpl%recv(nc0b,iproc,mpl%tag+1)
      end if

      ! Allocation
      allocate(c0b_to_c0(nc0b))
      allocate(c0a_to_c0b(nc0a))

      ! Communicate data
      if (iproc==mpl%ioproc) then
         ! Copy data
         c0b_to_c0 = obsop%c0b_to_c0
         c0a_to_c0b = obsop%c0a_to_c0b
      else
         ! Receive data on ioproc
         call mpl%recv(nc0b,c0b_to_c0,iproc,mpl%tag+2)
         call mpl%recv(nc0a,c0a_to_c0b,iproc,mpl%tag+3)
      end if

      ! Allocation
      com(iproc)%nred = nc0a
      com(iproc)%next = nc0b
      allocate(com(iproc)%ext_to_proc(com(iproc)%next))
      allocate(com(iproc)%ext_to_red(com(iproc)%next))
      allocate(com(iproc)%red_to_ext(com(iproc)%nred))

      ! Define halo origin
      do ic0b=1,nc0b
         ic0 = c0b_to_c0(ic0b)
         com(iproc)%ext_to_proc(ic0b) = geom%c0_to_proc(ic0)
         ic0a = c0_to_c0a(ic0)
         com(iproc)%ext_to_red(ic0b) = ic0a
      end do
      com(iproc)%red_to_ext = c0a_to_c0b

      ! Release memory
      deallocate(c0b_to_c0)
      deallocate(c0a_to_c0b)
   end do

   ! Release memory
   deallocate(c0_to_c0a)
else
   ! Send dimensions to ioproc
   call mpl%send(geom%nc0a,mpl%ioproc,mpl%tag)
   call mpl%send(obsop%nc0b,mpl%ioproc,mpl%tag+1)

   ! Send data to ioproc
   call mpl%send(obsop%nc0b,obsop%c0b_to_c0,mpl%ioproc,mpl%tag+2)
   call mpl%send(geom%nc0a,obsop%c0a_to_c0b,mpl%ioproc,mpl%tag+3)
end if
mpl%tag = mpl%tag+4
call obsop%com%setup(com,'com')

! Compute scores
if (mpl%main) then
   N_max = real(maxval(obsop%proc_to_nobsa),kind_real)/(real(obsop%nobs,kind_real)/real(mpl%nproc,kind_real))
   C_max = 0.0
   do iproc=1,mpl%nproc
      C_max = max(C_max,real(com(iproc)%nhalo,kind_real))
   end do
   C_max = C_max/(3.0*real(obsop%nobs,kind_real)/real(mpl%nproc,kind_real))
end if

! Print results
write(mpl%unit,'(a7,a)') '','Number of observations per MPI task:'
do iproc=1,mpl%nproc
   write(mpl%unit,'(a10,a,i3,a,i8)') '','Task ',iproc,': ',obsop%proc_to_nobsa(iproc)
end do
write(mpl%unit,'(a7,a,f5.1,a)') '','Observation repartition imbalance: ',100.0*real(maxval(obsop%proc_to_nobsa) &
 & -minval(obsop%proc_to_nobsa),kind_real)/(real(sum(obsop%proc_to_nobsa),kind_real)/real(mpl%nproc,kind_real)),' %'
write(mpl%unit,'(a7,a)') '','Number of grid points, halo size and number of received values per MPI task:'
if (mpl%main) then
   do iproc=1,mpl%nproc
      write(mpl%unit,'(a10,a,i3,a,i8,a,i8,a,i8)') '','Task ',iproc,': ', &
    & com(iproc)%nred,' / ',com(iproc)%next,' / ',com(iproc)%nhalo
   end do
else
   write(mpl%unit,'(a10,a,i3,a,i8,a,i8,a,i8)') '','Task ',mpl%myproc,': ', &
 & obsop%com%nred,' / ',obsop%com%next,' / ',obsop%com%nhalo
end if
if (mpl%main) write(mpl%unit,'(a7,a,f10.2,a,f10.2)') '','Scores (N_max / C_max):',N_max,' / ',C_max
call flush(mpl%unit)

if (mpl%main) then
   call mpl%newunit(lunit)

   ! Write observations
   open(unit=lunit,file=trim(nam%datadir)//'/'//trim(nam%prefix)//'_obs_out.dat',status='replace')
   do iobs=1,obsop%nobs
      write(lunit,*) lonobs(iobs)*rad2deg,latobs(iobs)*rad2deg
   end do
   close(unit=lunit)

   ! Write scores
   if (mpl%nproc>1) then
      call mpl%newunit(lunit)
      open(unit=lunit,file=trim(nam%datadir)//'/'//trim(nam%prefix)//'_obs_scores_'//trim(nam%obsdis)//'.dat',status='replace')
      write(lunit,*) N_max,C_max
      close(unit=lunit)
   end if
end if
if (mpl%main) then
   do iproc=1,mpl%nproc
      call com(iproc)%dealloc
   end do
end if

end subroutine obsop_parameters

!----------------------------------------------------------------------
! Subroutine: obsop_apply
!> Purpose: observation operator interpolation
!----------------------------------------------------------------------
subroutine obsop_apply(obsop,geom,fld,obs)

implicit none

! Passed variables
class(obsop_type),intent(in) :: obsop                    !< Observation operator data
type(geom_type),intent(in) :: geom                       !< Geometry
real(kind_real),intent(in) :: fld(geom%nc0a,geom%nl0)    !< Field
real(kind_real),intent(out) :: obs(obsop%nobsa,geom%nl0) !< Observations columns

! Local variables
integer :: il0
real(kind_real) :: fld_ext(obsop%nc0b,geom%nl0)

! Halo extension
call obsop%com%ext(geom%nl0,fld,fld_ext)

if (obsop%nobsa>0) then
   ! Horizontal interpolation
   !$omp parallel do schedule(static) private(il0)
   do il0=1,geom%nl0
      call obsop%h%apply(fld_ext(:,il0),obs(:,il0))
   end do
   !$omp end parallel do
end if

end subroutine obsop_apply

!----------------------------------------------------------------------
! Subroutine: obsop_apply_ad
!> Purpose: observation operator interpolation adjoint
!----------------------------------------------------------------------
subroutine obsop_apply_ad(obsop,geom,obs,fld)

implicit none

! Passed variables
class(obsop_type),intent(in) :: obsop                   !< Observation operator data
type(geom_type),intent(in) :: geom                      !< Geometry
real(kind_real),intent(in) :: obs(obsop%nobsa,geom%nl0) !< Observations columns
real(kind_real),intent(out) :: fld(geom%nc0a,geom%nl0)  !< Field

! Local variables
integer :: il0
real(kind_real) :: fld_ext(obsop%nc0b,geom%nl0)

if (obsop%nobsa>0) then
   ! Horizontal interpolation
   !$omp parallel do schedule(static) private(il0)
   do il0=1,geom%nl0
      call obsop%h%apply_ad(obs(:,il0),fld_ext(:,il0))
   end do
   !$omp end parallel do
end if

! Halo reduction
call obsop%com%red(geom%nl0,fld_ext,fld)

end subroutine obsop_apply_ad

!----------------------------------------------------------------------
! Subroutine: obsop_test_adjoint
!> Purpose: test observation operator adjoints accuracy
!----------------------------------------------------------------------
subroutine obsop_test_adjoint(obsop,geom)

implicit none

! Passed variables
class(obsop_type),intent(inout) :: obsop !< Observation operator data
type(geom_type),intent(in) :: geom       !< Geometry

! Local variables
real(kind_real) :: sum1,sum2
real(kind_real) :: fld(geom%nc0a,geom%nl0),fld_save(geom%nc0a,geom%nl0)
real(kind_real) :: yobs(obsop%nobsa,geom%nl0),yobs_save(obsop%nobsa,geom%nl0)

! Generate random fields
call rng%rand_real(0.0_kind_real,1.0_kind_real,fld_save)
call rng%rand_real(0.0_kind_real,1.0_kind_real,yobs_save)

! Apply direct and adjoint obsservation operators
call obsop%apply(geom,fld_save,yobs)
call obsop%apply_ad(geom,yobs_save,fld)

! Compute adjoint test
call mpl%dot_prod(fld,fld_save,sum1)
call mpl%dot_prod(yobs,yobs_save,sum2)
write(mpl%unit,'(a7,a,e15.8,a,e15.8,a,e15.8)') '','Observation operator adjoint test: ', &
 & sum1,' / ',sum2,' / ',2.0*abs(sum1-sum2)/abs(sum1+sum2)
call flush(mpl%unit)

end subroutine obsop_test_adjoint

!----------------------------------------------------------------------
! Subroutine: obsop_test_accuracy
!> Purpose: test observation operator accuracy
!----------------------------------------------------------------------
subroutine obsop_test_accuracy(obsop,geom)

implicit none

! Passed variables
class(obsop_type),intent(inout) :: obsop !< Observation operator data
type(geom_type),intent(in) :: geom       !< Geometry

! Local variables
integer :: ic0a,ic0,iobsa,iobs
integer :: iprocmax(1),iobsamax(1),iobsmax(1)
real(kind_real) :: ylonmax(1),ylatmax(1)
real(kind_real) :: norm,distmin,distmax,distsum
real(kind_real) :: norm_tot,distmin_tot,proc_to_distmax(mpl%nproc),distsum_tot
real(kind_real),allocatable :: lon(:,:),lat(:,:)
real(kind_real),allocatable :: ylon(:,:),ylat(:,:)
real(kind_real),allocatable :: dist(:)

! Allocation
allocate(ylon(obsop%nobsa,geom%nl0))
allocate(ylat(obsop%nobsa,geom%nl0))
allocate(lon(geom%nc0a,geom%nl0))
allocate(lat(geom%nc0a,geom%nl0))
allocate(dist(obsop%nobsa))

! Initialization
do ic0a=1,geom%nc0a
   ic0 = geom%c0a_to_c0(ic0a)
   lon(ic0a,:) = geom%lon(ic0)
   lat(ic0a,:) = geom%lat(ic0)
end do

! Apply obsop
call obsop%apply(geom,lon,ylon)
call obsop%apply(geom,lat,ylat)

! Remove points close to the longitude discontinuity and to the poles
call msr(dist)
do iobsa=1,obsop%nobsa
   iobs = obsop%obsa_to_obs(iobsa)
   if ((abs(obsop%lonobs(iobs))<0.8*pi).and.(abs(obsop%latobs(iobs))<0.4*pi)) then
      call sphere_dist(ylon(iobsa,1),ylat(iobsa,1),obsop%lonobs(iobs),obsop%latobs(iobs),dist(iobsa))
      dist(iobsa) = dist(iobsa)*reqkm
   end if
end do
norm = real(count(isnotmsr(dist)),kind_real)
if (norm>0) then
   distmin = minval(dist,mask=isnotmsr(dist))
   distmax = maxval(dist,mask=isnotmsr(dist))
   distsum = sum(dist,mask=isnotmsr(dist))
else
   distmin = huge(1.0)
   distmax = tiny(1.0)
   distsum = 0.0
end if

! Gather results
call mpl%allreduce_sum(norm,norm_tot)
call mpl%allreduce_min(distmin,distmin_tot)
call mpl%allgather(1,(/distmax/),proc_to_distmax)
call mpl%allreduce_sum(distsum,distsum_tot)

! Max. error detail
iprocmax = maxloc(proc_to_distmax)
if (iprocmax(1)==mpl%myproc) then
   iobsamax = maxloc(dist,mask=isnotmsr(dist))
   iobsmax = obsop%obsa_to_obs(iobsamax)
   ylonmax = ylon(iobsamax,1)
   ylatmax = ylat(iobsamax,1)
end if

! Broadcast results
call mpl%bcast(iobsmax,iprocmax(1))
call mpl%bcast(ylonmax,iprocmax(1))
call mpl%bcast(ylatmax,iprocmax(1))

! Print results
if (norm_tot>0.0) then
   write(mpl%unit,'(a7,a,f10.2,a,f10.2,a,f10.2,a)') '','Interpolation error (min/mean/max): ',distmin_tot, &
 & ' km / ',distsum_tot/norm_tot,' km / ',maxval(proc_to_distmax),' km'
   write(mpl%unit,'(a7,a)') '','Max. interpolation error location (lon/lat): '
   write(mpl%unit,'(a10,a14,f10.2,a,f10.2,a)') '','Observation:  ',obsop%lonobs(iobsmax(1))*rad2deg, &
 & ' deg. / ' ,obsop%latobs(iobsmax(1))*rad2deg,' deg.'
   write(mpl%unit,'(a10,a14,f10.2,a,f10.2,a)') '','Interpolation:',ylonmax*rad2deg, &
 & ' deg. / ' ,ylatmax*rad2deg,' deg.'
   call flush(mpl%unit)
else
   call msgerror('all observations are out of the test windows')
end if

end subroutine obsop_test_accuracy

end module type_obsop
