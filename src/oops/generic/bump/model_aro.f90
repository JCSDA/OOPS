!----------------------------------------------------------------------
! Module: module_aro.f90
!> Purpose: AROME model routines
!> <br>
!> Author: Benjamin Menetrier
!> <br>
!> Licensing: this code is distributed under the CeCILL-C license
!> <br>
!> Copyright © 2015-... UCAR, CERFACS and METEO-FRANCE
!----------------------------------------------------------------------
module model_aro

use netcdf
use tools_const, only: deg2rad,rad2deg,req,ps
use tools_display, only: msgerror
use tools_kinds,only: kind_real
use tools_missing, only: msvalr,msr,isanynotmsr
use tools_nc, only: ncerr,ncfloat
use type_geom, only: geom_type
use type_mpl, only: mpl
use type_nam, only: nam_type

implicit none

private
public :: model_aro_coord,model_aro_read

character(len=1024) :: zone = 'C+I' !< Computation zone ('C', 'C+I' or 'C+I+E')

contains

!----------------------------------------------------------------------
! Subroutine: model_aro_coord
!> Purpose: load AROME coordinates
!----------------------------------------------------------------------
subroutine model_aro_coord(nam,geom)

implicit none

! Passed variables
type(nam_type),intent(in) :: nam      !< Namelist
type(geom_type),intent(inout) :: geom !< Geometry

! Local variables
integer :: ncid,nlon_id,nlat_id,nlev_id,pp_id,lon_id,lat_id,cmask_id,a_id,b_id
integer :: il0,ic0,ilon,ilat
real(kind_real) :: dx,dy
real(kind=8),allocatable :: lon(:,:),lat(:,:),cmask(:,:),a(:),b(:)
logical,allocatable :: cmask_pack(:)
character(len=1024) :: subr = 'model_aro_coord'

! Open file and get dimensions
call ncerr(subr,nf90_open(trim(nam%datadir)//'/grid.nc',nf90_nowrite,ncid))
call ncerr(subr,nf90_inq_dimid(ncid,'X',nlon_id))
call ncerr(subr,nf90_inq_dimid(ncid,'Y',nlat_id))
call ncerr(subr,nf90_inquire_dimension(ncid,nlon_id,len=geom%nlon))
call ncerr(subr,nf90_inquire_dimension(ncid,nlat_id,len=geom%nlat))
geom%nmg = geom%nlon*geom%nlat
call ncerr(subr,nf90_inq_dimid(ncid,'Z',nlev_id))
call ncerr(subr,nf90_inquire_dimension(ncid,nlev_id,len=geom%nlev))

! Allocation
allocate(lon(geom%nlon,geom%nlat))
allocate(lat(geom%nlon,geom%nlat))
allocate(cmask(geom%nlon,geom%nlat))
allocate(cmask_pack(geom%nmg))
allocate(a(geom%nlev+1))
allocate(b(geom%nlev+1))

! Read data and close file
call ncerr(subr,nf90_inq_varid(ncid,'longitude',lon_id))
call ncerr(subr,nf90_inq_varid(ncid,'latitude',lat_id))
call ncerr(subr,nf90_inq_varid(ncid,'cmask',cmask_id))
call ncerr(subr,nf90_inq_varid(ncid,'hybrid_coef_A',a_id))
call ncerr(subr,nf90_inq_varid(ncid,'hybrid_coef_B',b_id))
call ncerr(subr,nf90_inq_varid(ncid,'Projection_parameters',pp_id))
call ncerr(subr,nf90_get_var(ncid,lon_id,lon))
call ncerr(subr,nf90_get_var(ncid,lat_id,lat))
call ncerr(subr,nf90_get_var(ncid,cmask_id,cmask))
call ncerr(subr,nf90_get_var(ncid,a_id,a))
call ncerr(subr,nf90_get_var(ncid,b_id,b))
call ncerr(subr,nf90_get_att(ncid,pp_id,'x_resolution',dx))
call ncerr(subr,nf90_get_att(ncid,pp_id,'y_resolution',dy))
call ncerr(subr,nf90_close(ncid))

! Convert to radian
lon = lon*real(deg2rad,kind=8)
lat = lat*real(deg2rad,kind=8)

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
      geom%lon(ic0) = real(lon(ilon,ilat),kind_real)
      geom%lat(ic0) = real(lat(ilon,ilat),kind_real)
      select case (trim(zone))
      case ('C')
         geom%mask(ic0,:) = (cmask(ilon,ilat)>0.75)
      case ('C+I')
         geom%mask(ic0,:) = (cmask(ilon,ilat)>0.25)
      case ('C+I+E')
         geom%mask(ic0,:) = .true.
      case default
         call msgerror('wrong AROME zone')
      end select
   end do
end do

! Compute normalized area
do il0=1,geom%nl0
   geom%area(il0) = float(count(geom%mask(:,il0)))*dx*dy/req**2
end do

! Vertical unit
if (nam%logpres) then
   geom%vunit(1:nam%nl) = log(0.5*(a(nam%levs(1:nam%nl))+a(nam%levs(1:nam%nl)+1)) &
                        & +0.5*(b(nam%levs(1:nam%nl))+b(nam%levs(1:nam%nl)+1))*ps)
   if (geom%nl0>nam%nl) geom%vunit(geom%nl0) = log(ps)
else
   geom%vunit = float(nam%levs(1:geom%nl0))
end if

! Release memory
deallocate(lon)
deallocate(lat)
deallocate(cmask)
deallocate(a)
deallocate(b)

end subroutine model_aro_coord

!----------------------------------------------------------------------
! Subroutine: model_aro_read
!> Purpose: read AROME field
!----------------------------------------------------------------------
subroutine model_aro_read(nam,geom,filename,fld)

implicit none

! Passed variables
type(nam_type),intent(in) :: nam                              !< Namelist
type(geom_type),intent(in) :: geom                            !< Geometry
character(len=*),intent(in) :: filename                       !< File name
real(kind_real),intent(out) :: fld(geom%nc0a,geom%nl0,nam%nv) !< Field

! Local variables
integer :: iproc,iv,il0,ic0a,ic0,ilon,ilat
integer :: ncid,fld_id
real(kind_real) :: fld_loc
character(len=3) :: ilchar
character(len=1024) :: subr = 'model_aro_read'

! Initialize field
call msr(fld)

do iproc=1,mpl%nproc
   if (mpl%myproc==iproc) then
      ! Open file
      call ncerr(subr,nf90_open(trim(nam%datadir)//'/'//trim(filename),nf90_nowrite,ncid))
   
      do iv=1,nam%nv
         ! 3d variable
         do il0=1,nam%nl
            ! Get id
            write(ilchar,'(i3.3)') nam%levs(il0)
            call ncerr(subr,nf90_inq_varid(ncid,'S'//ilchar//trim(nam%varname(iv)),fld_id))
   
            ! Read data
            do ic0a=1,geom%nc0a
               ic0 = geom%c0a_to_c0(ic0a)
               ilon = geom%c0_to_lon(ic0)
               ilat = geom%c0_to_lat(ic0)
               call ncerr(subr,nf90_get_var(ncid,fld_id,fld_loc,(/ilon,ilat/)))
               fld(ic0a,il0,iv) = real(fld_loc,kind_real)
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
                  call ncerr(subr,nf90_get_var(ncid,fld_id,fld_loc,(/ilon,ilat/)))
                  fld(ic0a,geom%nl0,iv) = real(fld_loc,kind_real)
               end do
   
               ! Variable change for surface pressure
              if (trim(nam%addvar2d(iv))=='SURFPRESSION') fld(:,geom%nl0,iv) = exp(fld(:,geom%nl0,iv))
            end if
         end do
      end do

      ! Close file
      call ncerr(subr,nf90_close(ncid))
   end if

   ! Wait
   call mpl%barrier
end do

end subroutine model_aro_read

end module model_aro
