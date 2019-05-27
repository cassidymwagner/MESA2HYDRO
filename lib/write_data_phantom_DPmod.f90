!-----------------------------------------------------------------
!
!  This file is (or was) part of SPLASH, a visualisation tool
!  for Smoothed Particle Hydrodynamics written by Daniel Price:
!
!  http://users.monash.edu.au/~dprice/splash
!
!  SPLASH comes with ABSOLUTELY NO WARRANTY.
!  This is free software; and you are welcome to redistribute
!  it under the terms of the GNU General Public License
!  (see LICENSE file for details) and the provision that
!  this notice remains intact. If you modify this file, please
!  note section 2a) of the GPLv2 states that:
!
!  a) You must cause the modified files to carry prominent notices
!     stating that you changed the files and the date of any change.
!
!  Copyright (C) 2005-2019 Daniel Price. All rights reserved.
!  Contact: daniel.price@monash.edu
!
!-----------------------------------------------------------------

!-----------------------------------------------------------------
! Module implementing "splash to phantom" operation, writing
! a binary dump file suitable for input to the PHANTOM code
!-----------------------------------------------------------------
module write_data_phantom_DPmod
 use iso_c_binding, only:c_float,c_double
 implicit none
 integer, parameter :: int8 = selected_int_kind(10)
 integer, parameter :: sing_prec = c_float
 integer, parameter :: doub_prec = c_double
 character(len=10), parameter, public :: formatname='phantom'
 integer, parameter :: lentag = 16

 public :: write_sphdata_phantom
 private

contains

function tag(string)
 character(len=lentag) :: tag
 character(len=*), intent(in) :: string

 tag = adjustl(string)

end function tag

subroutine write_sphdata_phantom(time,gamma,dat,ndim,ntotal,ntypes,npartoftype, &
                                 masstype,ncolumns,udist,umass,utime,umagfd,labeltype,&
                                 label_dat,ix,ih,ivx,iBfirst,ipmass,iutherm,filename)
 integer, intent(in)          :: ndim,ntotal,ntypes,ncolumns
 integer, intent(in)          :: npartoftype(:)
 real, intent(in)             :: time,gamma
 real, intent(in)             :: dat(ntotal,ncolumns)
 real, intent(in)             :: masstype(:)
 real(doub_prec), intent(in)  :: udist,umass,utime,umagfd
 character(len=*), intent(in) :: labeltype(ntypes),label_dat(ncolumns)
 integer,          intent(in) :: ix(3),ivx,ih,iBfirst,ipmass,iutherm
 character(len=*), intent(in) :: filename

 integer, parameter    :: i_int   = 1, &
                          i_int1  = 2, &
                          i_int2  = 3, &
                          i_int4  = 4, &
                          i_int8  = 5, &
                          i_real  = 6, &
                          i_real4 = 7, &
                          i_real8 = 8
 integer, parameter    :: idump = 83
 character(len=len(filename)+10) :: outfile

 integer, parameter :: intval1=690706,intval2=780806
 integer, parameter :: int1o=690706 !,int2o=780806
 integer, parameter :: idimhead = 22
 integer(kind=int8) :: nparttot,npartoftypetot(ntypes),number8
 integer            :: nums(8)
 integer            :: narraylengths,nblocks,nblockarrays,ntypesi
 integer            :: i,j,ierr,i1,index1,number,npart,nptmass,iversion,np
 real               :: rheader(idimhead)
 character(len=lentag) :: rheader_tags(idimhead)
 real               :: r1,hfact
 logical            :: mhd
!
! sink particle locations in dat array
!
 integer, allocatable :: ilocsink(:)
!
!--define output file name
!
 outfile=trim(filename)//'.tmp'
 narraylengths = 2
 nblocks = 1          ! not parallel dump
 hfact   = 1.2        ! must be specified in phantom dumps
 nptmass = 0          ! work this out later
!
!--check if we have enough data to write a PHANTOM dump
!
 if (ndim < 3) then
    print "(a)",' ERROR: ndim < 3 but must be 3 for PHANTOM data -- cannot write PHANTOM dump, skipping...'
    return
 endif
 if (any(ix(:) <= 0)) then
    print "(a)",' ERROR: position labels not set -- cannot write PHANTOM dump, skipping...'
    return
 endif
 if (ivx <= 0) then
    print "(a)",' ERROR: velocity not found in data -- cannot write PHANTOM dump, skipping...'
    return
 endif
 if (ih <= 0) then
    print "(a)",' ERROR: smoothing length not found in data -- cannot write PHANTOM dump, skipping...'
    return
 endif
 mhd = .false.
 if (iBfirst > 0) then
    mhd = .true.
    narraylengths = 4
 endif
!--fill rheader and check that we have equal mass particles
 rheader_tags = ' '
 rheader(:) = 0.
 rheader(1) = time
 rheader(3) = gamma
 rheader(6) = hfact
 rheader_tags(1) = 'time'
 rheader_tags(3) = 'gamma'
 rheader_tags(6) = 'hfact'
 if (ipmass > 0) then
    index1 = 1
    do i=1,ntypes
       rheader(14+i) = dat(index1,ipmass)
       rheader_tags(14+i) = 'massoftype'
       if (npartoftype(i) > 0) then
          if (any(dat(index1:index1+npartoftype(i)-1,ipmass).ne.dat(index1,ipmass))) then
             print*,' WARNING: unequal mass particles detected but PHANTOM only accepts equal mass, skipping...'
             return
          endif
          index1 = index1 + npartoftype(i) - 1
       endif
    enddo
 else
    do i=1,ntypes
       rheader(14+i) = masstype(i)
       rheader_tags(14+i) = 'massoftype'
    enddo
 endif

 write(*,"(/,/,'-------->   TIME = ',f10.4,"// &
              "': full dump written to file ',a,' on unit ',i2,'   <--------',/)") &
       time,trim(outfile),idump

 open(unit=idump,file=outfile,status='new',form='unformatted',iostat=ierr)
 if (ierr /= 0) then
    write(*,*) 'error: can''t create new dumpfile '//trim(outfile)
    return
 endif
!
!--write full dump Phantom/sphNG file
!
 i1 = intval1
 r1 = real(intval2)
 iversion = 1 ! file version to write
 write (idump, err=100) intval1,r1,intval2,iversion,int1o
 write (idump, err=100) fileident('F','Phantom',mhd=mhd)

!
!--figure out whether we have sink particles
!
 call extract_sink_particles_from_data(ntypes,npartoftype,labeltype,np,nptmass,ntypesi,ilocsink)

 npart = npartoftype(1)
 npartoftypetot(:) = 0
 do i=2,ntypesi
    npart = npart + npartoftype(i)
    if (npartoftype(i) > 0) print "(a)",' WARNING: assuming '// &
        trim(labeltype(i))//' particles are same as gas particles'
    if (rheader(15) <= 0.) then
        rheader(15) = masstype(i)
        rheader(15+i) = 0.
    elseif (abs(masstype(i)-rheader(15)) < tiny(masstype)) then
        print*,' WARNING! WARNING! mass of '//trim(labeltype(i))// &
              ' particles differs from '//trim(labeltype(1))//' particles'
        print*,' Assuming all particles have '//trim(labeltype(1))//' particle mass'
    endif
 enddo
 npartoftypetot(1) = npart
 nparttot = npart
!
!--single values
!
!--default int
 number = 8
 write (idump, err=100) number
 write (idump, err=100) tag('nparttot'),tag('ntypes'),(tag('npartoftype'),i=1,5),tag('nblocks')
 write (idump, err=100) int(nparttot),ntypesi,(int(npartoftypetot(i)),i=1,5),nblocks
!--int*1, int*2, int*4
 number = 0
 do i = 1, 3
    write (idump, err=100) number
 end do
!--int*8
 number = 2 + ntypes
 write (idump, err=100) number
 write (idump, err=100) tag('nparttot'),tag('ntypes'),(tag('npartoftypet'),i=1,ntypesi)
 write (idump, err=100) nparttot,int(ntypesi,kind=8),npartoftypetot(1:ntypesi)

!--default real

 write (idump, err=100) idimhead
 write (idump, err=100) rheader_tags(1:idimhead)
 write (idump, err=100) rheader(1:idimhead)

!--real*4
 number = 0
 write (idump, err=100) number
!--real*8
 if (umagfd > 0.) then
    number = 4
    write (idump, err=100) number
    write (idump, err=100) tag('udist'),tag('umass'),tag('utime'),tag('umagfd')
    write (idump, err=100) udist, umass, utime, umagfd
 else
    number = 3
    write (idump, err=100) number
    write (idump, err=100) tag('udist'),tag('umass'),tag('utime')
    write (idump, err=100) udist, umass, utime
 endif

 nblockarrays = narraylengths*nblocks
 write (idump, err=100) nblockarrays
!
!--array length 1 header
!
 number8 = npart
 nums(:) = 0
 if (iutherm.gt.0) then
    nums(i_real) = 7
 else
    nums(i_real) = 6
 endif
 nums(i_real4) = 1
 write (idump, err=100) number8, (nums(i), i=1,8)
!
!--array length 2 header
!
 number8 = nptmass
 nums(:) = 0
 write (idump, err=100) number8, (nums(i), i=1,8)
!
!--array length 3 header
!
 if (narraylengths >= 3) then
    number8 = 0
    nums(1:8) = 0
    write (idump, err=100) number8, (nums(i), i=1,8)
 endif
!
!--array length 4 header
!
 if (narraylengths >= 4) then
    if (mhd) then
       number8 = npart
    else
       number8 = 0
    endif
    nums(:) = 0
    if (mhd) nums(i_real4) = 3
    write (idump, err=100) number8, (nums(i), i=1,8)
 endif

!
!--array length 1 arrays
!
!--default int
!--int*1
!--int*2
!--int*4
!--int*8
!--default real
 do j = 1, 3
    write (idump, err=100) tag(label_dat(ix(j)))
    write (idump, err=100) (dat(i,ix(j)), i=1, np)
 end do

 do j = 1, 3
    write (idump, err=100) tag(label_dat(ivx+j-1))
    write (idump, err=100) (dat(i,ivx+j-1), i=1, np)
 end do

 if (iutherm.gt.0) then
    write (idump, err=100) tag(label_dat(iutherm))
    write (idump, err=100) (dat(i,iutherm), i=1, np)
 endif

!--real*4
!   dump smoothing length as a real*4 to save space
 write (idump, err=100) tag(label_dat(ih))
 write (idump, err=100) (real(dat(i,ih),kind=sing_prec), i=1, np)
!
!--sink particle arrays
!
 if (nptmass > 0) then
    do j = 1, 3
       write (idump, err=100) tag(label_dat(ix(j)))
       write (idump, err=100) (dat(ilocsink(i),ix(j)),i=1,nptmass)
    enddo
    write (idump, err=100) tag(label_dat(ipmass))
    write (idump, err=100) (dat(ilocsink(i),ipmass),i=1,nptmass)
    write (idump, err=100) tag(label_dat(ih))
    write (idump, err=100) (dat(ilocsink(i),ih),i=1,nptmass)
!    write (idump, err=100) (hsoft,i=1,nptmass)
!    write (idump, err=100) (macc,i=1,nptmass)
!    write (idump, err=100) (spinx,i=1,nptmass)
!    write (idump, err=100) (spinx,i=1,nptmass)
!    write (idump, err=100) (spinx,i=1,nptmass)
    do j = 1, 3
       write (idump, err=100) tag(label_dat(ivx+j-1))
       write (idump, err=100) (dat(ilocsink(i),ivx+j-1),i=1,nptmass)
    enddo
 endif

 if (mhd) then
    do j=1,3
       write(idump,err=100) (real(dat(i,iBfirst+j-1),kind=sing_prec),i=1, np)
    enddo
 endif

 close(unit=idump)
 return

100 continue
 write(*,*) 'error whilst writing dumpfile '//trim(outfile)
 close(unit=idump)

end subroutine write_sphdata_phantom

!--------------------------------------------------------------------
!+
!  contruct header string based on compile-time options
!  these are for information only (ie. not important for restarting)
!+
!--------------------------------------------------------------------
character(len=100) function fileident(firstchar,codestring,mhd)
 implicit none
 character(len=1), intent(in) :: firstchar
 character(len=*), intent(in), optional :: codestring
 logical,          intent(in), optional :: mhd
 character(len=10) :: datestring, timestring, string
 logical :: gotmhd
!
!--print date and time stamp in file header
!
 call date_and_time(datestring,timestring)
 datestring = datestring(7:8)//'/'//datestring(5:6)//'/'//datestring(1:4)
 timestring = timestring(1:2)//':'//timestring(3:4)//':'//timestring(5:)

 string = ' '

 if (present(codestring)) then
    fileident = firstchar//'T:'//trim(codestring)
 else
    fileident = firstchar//'T:Phantom'
 endif

 gotmhd = .false.
 if (present(mhd)) gotmhd = mhd
 if (gotmhd) then
    fileident = trim(fileident)//' (mhd'//trim(string)//')  : '//trim(datestring)//' '//trim(timestring)
 else
    fileident = trim(fileident)//' (hydro'//trim(string)//'): ' &
                //trim(datestring)//' '//trim(timestring)
 endif

end function fileident

!--------------------------------------------------------------------
!+
!  extract sink particle information from dat array, as these arrays
!  are written separately in phantom data files
!+
!--------------------------------------------------------------------
subroutine extract_sink_particles_from_data(ntypes,npartoftype,labeltype,np,nptmass,ntypesi,ilocsink)
 integer, intent(in) :: ntypes,npartoftype(ntypes)
 character(len=*), intent(in) :: labeltype(ntypes)
 integer, intent(out) :: np,nptmass,ntypesi
 integer, allocatable, intent(out) :: ilocsink(:)
 integer :: i,j

 np = 0
 ntypesi = ntypes
 over_types: do i=1,ntypes
    if (trim(labeltype(i))=='sink' .or. trim(labeltype(i))=='dark matter') then
       nptmass = npartoftype(i)
       allocate(ilocsink(nptmass))
       do j=1,nptmass
          ilocsink(j) = np+j
       enddo
       ntypesi = ntypes - 1  ! do not write types after this
       exit over_types
    else
       np = np + npartoftype(i)
    endif
 enddo over_types
 if (nptmass > 0) print "(/,a,i2,a)",' WRITING ',nptmass,' SINK PARTICLES'

end subroutine extract_sink_particles_from_data

end module write_data_phantom_DPmod
