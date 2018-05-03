!----------------------------------------------------------------------
! Module: module_gfs.f90
!> Purpose: GFS model routines
!> <br>
!> Author: Benjamin Menetrier
!> <br>
!> Licensing: this code is distributed under the CeCILL-C license
!> <br>
!> Copyright © 2015-... UCAR, CERFACS and METEO-FRANCE
!----------------------------------------------------------------------
module model_gfs

use netcdf
use tools_const, only: pi,deg2rad,rad2deg,ps
use tools_display, only: msgerror
use tools_kinds,only: kind_real
use tools_missing, only: msvalr,msr,isanynotmsr
use tools_nc, only: ncerr,ncfloat
use type_geom, only: geom_type
use type_mpl, only: mpl
use type_nam, only: nam_type

implicit none

private
public :: model_gfs_coord,model_gfs_read

contains

!----------------------------------------------------------------------
! Subroutine: model_gfs_coord
!> Purpose: get GFS coordinates
!----------------------------------------------------------------------
subroutine model_gfs_coord(nam,geom)

implicit none

! Passed variables
type(nam_type),intent(in) :: nam      !< Namelist
type(geom_type),intent(inout) :: geom !< Geometry

! Local variables
integer :: ilon,ilat,ic0
integer :: ncid,nlon_id,nlat_id,nlev_id,lon_id,lat_id,a_id,b_id
real(kind=4),allocatable :: lon(:),lat(:),a(:),b(:)
character(len=1024) :: subr = 'model_gfs_coord'

! Open file and get dimensions
call ncerr(subr,nf90_open(trim(nam%datadir)//'/grid.nc',nf90_nowrite,ncid))
call ncerr(subr,nf90_inq_dimid(ncid,'longitude',nlon_id))
call ncerr(subr,nf90_inq_dimid(ncid,'latitude',nlat_id))
call ncerr(subr,nf90_inquire_dimension(ncid,nlon_id,len=geom%nlon))
call ncerr(subr,nf90_inquire_dimension(ncid,nlat_id,len=geom%nlat))
geom%nmg = geom%nlon*geom%nlat
call ncerr(subr,nf90_inq_dimid(ncid,'level',nlev_id))
call ncerr(subr,nf90_inquire_dimension(ncid,nlev_id,len=geom%nlev))

! Allocation
allocate(lon(geom%nlon))
allocate(lat(geom%nlat))
allocate(a(geom%nlev+1))
allocate(b(geom%nlev+1))

! Read data and close file
call ncerr(subr,nf90_inq_varid(ncid,'longitude',lon_id))
call ncerr(subr,nf90_inq_varid(ncid,'latitude',lat_id))
call ncerr(subr,nf90_inq_varid(ncid,'ak',a_id))
call ncerr(subr,nf90_inq_varid(ncid,'bk',b_id))
call ncerr(subr,nf90_get_var(ncid,lon_id,lon))
call ncerr(subr,nf90_get_var(ncid,lat_id,lat))
call ncerr(subr,nf90_get_var(ncid,a_id,a))
call ncerr(subr,nf90_get_var(ncid,b_id,b))
call ncerr(subr,nf90_close(ncid))

! Convert to radian
lon = lon*real(deg2rad,kind=4)
lat = lat*real(deg2rad,kind=4)

! Not redundant grid
call geom%find_redundant

! Pack
call geom%alloc
ic0 = 0
do ilon=1,geom%nlon
   do ilat=1,geom%nlat
      ic0 = ic0+1
      geom%c0_to_lon(ic0) = ilon
      geom%c0_to_lat(ic0) = ilat
      geom%lon(ic0) = real(lon(ilon),kind_real)
      geom%lat(ic0) = real(lat(ilat),kind_real)
      geom%mask(ic0,:) = .true.
   end do
end do

! Compute normalized area
geom%area = 4.0*pi

! Vertical unit
do ic0=1,geom%nc0
   if (nam%logpres) then
      geom%vunit(ic0,1:nam%nl) = log(0.5*(a(nam%levs(1:nam%nl))+a(nam%levs(1:nam%nl)+1)) &
                           & +0.5*(b(nam%levs(1:nam%nl))+b(nam%levs(1:nam%nl)+1))*ps)
      if (geom%nl0>nam%nl) geom%vunit(ic0,geom%nl0) = log(ps)
   else
      geom%vunit(ic0,:) = real(nam%levs(1:geom%nl0),kind_real)
   end if
end do

! Release memory
deallocate(lon)
deallocate(lat)
deallocate(a)
deallocate(b)

end subroutine model_gfs_coord

!----------------------------------------------------------------------
! Subroutine: model_gfs_read
!> Purpose: read GFS field
!----------------------------------------------------------------------
subroutine model_gfs_read(nam,geom,filename,fld)

implicit none

! Passed variables
type(nam_type),intent(in) :: nam                              !< Namelist
type(geom_type),intent(in) :: geom                            !< Geometry
character(len=*),intent(in) :: filename                       !< File name
real(kind_real),intent(out) :: fld(geom%nc0a,geom%nl0,nam%nv) !< Field

! Local variables
integer :: iv,il0,ic0a,ic0,ilon,ilat,iproc
integer :: ncid,fld_id
real(kind=4) :: fld_tmp
character(len=1024) :: subr = 'model_gfs_read'

! Initialize field
call msr(fld)

do iproc=1,mpl%nproc
   if (mpl%myproc==iproc) then
      ! Open file
      call ncerr(subr,nf90_open(trim(nam%datadir)//'/'//trim(filename),nf90_nowrite,ncid))

      do iv=1,nam%nv
         ! 3d variable

         ! Get variable id
         call ncerr(subr,nf90_inq_varid(ncid,trim(nam%varname(iv)),fld_id))

         ! 3d variable
         do il0=1,nam%nl
            do ic0a=1,geom%nc0a
               ic0 = geom%c0a_to_c0(ic0a)
               ilon = geom%c0_to_lon(ic0)
               ilat = geom%c0_to_lat(ic0)
               call ncerr(subr,nf90_get_var(ncid,fld_id,fld_tmp,(/ilon,ilat,nam%levs(il0)/)))
               fld(ic0a,il0,iv) = real(fld_tmp,kind_real)
            end do
         end do

         if (trim(nam%addvar2d(iv))/='') then
            ! 2d variable

            ! Get id
            call ncerr(subr,nf90_inq_varid(ncid,trim(nam%addvar2d(iv)),fld_id))

            ! Read data
            do ic0a=1,geom%nc0a
               ic0 = geom%c0a_to_c0(ic0a)
               ilon = geom%c0_to_lon(ic0)
               ilat = geom%c0_to_lat(ic0)
               call ncerr(subr,nf90_get_var(ncid,fld_id,fld_tmp,(/ilon,ilat/)))
               fld(ic0a,geom%nl0,iv) = real(fld_tmp,kind_real)
            end do
         end if
      end do

      ! Close file
      call ncerr(subr,nf90_close(ncid))
   end if

   ! Wait
   call mpl%barrier
end do

end subroutine model_gfs_read

end module model_gfs
