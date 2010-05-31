      PROGRAM Cgrid

C *****************************************************************************
C
C           GENERATES C-TYPE STRUCTURED GRID AROUND AN AIRFOIL
C           ==================================================
C
C                 (c) Jiri Blazek, created Feb. 14, 1995
C                     Version 2.1 from Sep. 05, 2004
C
C *****************************************************************************
C Modifications by Praveen. C:
C     Input file must contain kulfan parameters instead of airfoil
C     coordinates. These are generated by running fit_kulfan.m
C *****************************************************************************
C
C   Features:
C   ~~~~~~~~~
C   # body-fitted C-grid
C   # elliptic grid smoothing (Laplace or Poisson equation solved with
C     Gauss-Seidel iterative scheme)
C   # wall contour approximated using Bezier spline change
C   # point clustering at leading and trailing edge
C   # adjustable wall spacing in wall layer
C   # adjustable distance to farfield
C   # writes grid and topology file in STRUCT2D format
C   # writes plot file in Vis2D format
C
C   I/O channels:
C   ~~~~~~~~~~~~~
C   5  = user parameters (input)
C   6  = control output
C   10 = grid data (fn_grid)
C   20 = grid topology (fn_gtop)
C   30 = plot data (fn_plot, Vis2D format)
C
C *****************************************************************************
C
C  Subroutines called: Bezier, Bezier_interpol, Bezier_x, Sstretch,
C                      Stretch, Tfint
C
C  Functions called: Length
C
C *****************************************************************************
C
C   This program is free software; you can redistribute it and/or
C   modify it under the terms of the GNU General Public License
C   as published by the Free Software Foundation; either version 2
C   of the License, or (at your option) any later version.
C
C   This program is distributed in the hope that it will be useful,
C   but WITHOUT ANY WARRANTY; without even the implied warranty of
C   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
C   GNU General Public License for more details.
C
C   You should have received a copy of the GNU General Public License
C   along with this program; if not, write to the Free Software
C   Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
C
C *****************************************************************************

      IMPLICIT NONE

C ... global dimensions - set as appropriate
      INTEGER im, jm
      PARAMETER (im=387, jm=67)

C ... global variables
      CHARACTER*80 title
      CHARACTER*48 fn_grid, fn_gtop, fn_plot
      INTEGER nxa, nxw, ny, ncoo, ip, jp, nle, ntel, nteu, narcl,
     &        narcu, itlapla, itsmoo, itgauss, icd, jcd, ica, jca
      REAL*8 xya(2,im), x(im,jm), y(im,jm), bc(2,3*im+1)
      REAL*8 ffdist, dyle, dyte, dxte, dywk, damps, dampa, pspace,
     &       pangle, omega, xcirc

C ... loop variables
      INTEGER i, j

C ... local variables
      INTEGER ii, i1, i2, nc
      REAL*8 s1(jm), s2(jm), s3(im), s4(im)
      REAL*8 p(im,jm), q(im,jm), distes(im,jm), angles(im,jm)
      REAL*8 pi, ang, vp, vple, xle, x1, x2, d, dxe, dxs, dx, dy, sr, a

C ... functions
      INTEGER Length

      INTEGER bzdeg,r !  ,c,i,j  already covered above
      !   PARAMETER (c=1) already covered above
      REAL*8 N1,N2,zite_l,zite_u
      Real*8 al(100),au(100)
      Real*8 shap, psi
      Real*8 decas
      Real*8 thetal, thetau, thetate, xi
      Real*8 teclust


C *****************************************************************************

      pi = 4.D0*DATAN(1.D0)
      ncoo = 0

      WRITE(*,*) ' '
      WRITE(*,*) '*************************************************'
      WRITE(*,*) '*                                               *'
      WRITE(*,*) '*    GENERATION OF 2-D C-GRID AROUND AIRFOIL    *'
      WRITE(*,*) '*                                               *'
      WRITE(*,*) '*      (c) Jiri Blazek, V. 2.1, 09/05/2004      *'
      WRITE(*,*) '*                                               *'
      WRITE(*,*) '*************************************************'
      WRITE(*,*) ' '

C --- read parameters and airfoil coordinates ---------------------------------
      READ(*,*)
      READ(*,*) title
      READ(*,*)
      READ(*,*)
      READ(*,*) fn_grid
      READ(*,*)
      READ(*,*)
      READ(*,*) fn_gtop
      READ(*,*)
      READ(*,*)
      READ(*,*) fn_plot
      READ(*,*)
      READ(*,*) nxa        ! no. of cells around airfoil (new distrib.)
      READ(*,*) nxw        ! no. of cells in wake
      READ(*,*) ny         ! no. of cells in normal direct.
      READ(*,*) ffdist     ! far field distance
      READ(*,*) dyle       ! leading edge spacing in y-dir.
      READ(*,*) dxte       ! trailing edge spacing in x-dir.
      READ(*,*) dyte       ! trailing edge spacing in y-dir.
      READ(*,*) dywk       ! spacing at wake exit in y-dir.
      READ(*,*) itlapla    ! max. no. of iterations for Laplace's smoothing
      READ(*,*) itsmoo     ! max. no. of grid smoothing iterations (itlapla>0)
      READ(*,*) itgauss    ! max. no. of Gauss-Seidel iterations
      READ(*,*) damps      ! spacing damping factor
      READ(*,*) pspace     ! decay of given spacing from wall into field
      READ(*,*) dampa      ! angle damping factor
      READ(*,*) pangle     ! decay of angle distribution from wall into field
      READ(*,*) omega      ! overrelaxation factor
      READ(*,*) N1
      Write(*,*) 'N1:' ,N1
      READ(*,*) N2
      Write(*,*) 'N2:' ,N2
      READ(*,*) bzdeg
      WRITE(*,*) 'degree:', bzdeg
      read(*,*)            !read bezier coefficients for upper surface
      DO r=0, bzdeg
        READ(*,*) al(r+1)
      ENDDO
      WRITE(*,*) 'coefficients of lower curve:',(al(r),r=1,bzdeg+1)
      READ(*,*) zite_l
      WRITE(*,*) 'zi value of trailing edge for lower surface:', zite_l
      read(*,*)   !now read bezier coefficients for upper surface
      DO r=0,bzdeg
        READ(*,*) au(r+1)
      ENDDO
      WRITE(*,*) 'coefficients of upper curve:',(au(r),r=1,bzdeg+1)
      READ(*,*) zite_u
      WRITE(*,*) 'zi value of trailing edge for upper surface:', zite_l
      
      if(zite_l .ne. zite_u)then
         write(*,*)'zite_l is not equal to zite_u'
         stop
      endif

      if(mod(nxa,2).ne.0)then
         write(*,*)'nxa must be even, nxa =',nxa
         stop
      endif
      ip = nxa + 2*nxw + 1       ! no. of points in i-, j-direction
      jp = ny + 1
      IF (ip.GT.im .OR. jp.GT.jm) THEN
        WRITE(*,'(A)') 'ERROR - too many grid points !'
        GOTO 9999
      ENDIF
      nle  = nxa/2 + nxw + 1     ! l.e. index
      ntel = nxw + 1             ! t.e. (lower surface) index
      nteu = ntel + nxa          !  ''  (upper  - '' -) -''-

      WRITE(*,1000) ip,jp,nle,ntel,nteu

c     We assume LE is at x=0
      xle  = 0.0

C --- distribute points on airfoil --------------------------------------------

      WRITE(*,'(A)') ' Distributing points on airfoil ...'
      
      x(ntel,1) = 1.D0
      y(ntel,1) = zite_l
      x(nle ,1) = 0.D0
      y(nle ,1) = 0.D0
      x(nteu,1) = 1.D0
      y(nteu,1) = zite_u

C     TE clustering: 1.0 will do lot of clustering but can give bad grid
      teclust = 0.9D0

C     Lower surface
      DO i=ntel+1,nle-1
       ang= REAL(i-nle)*teclust*pi/REAL(ntel-nle)
       psi = (1.D0-COS(ang))/(1.D0-COS(teclust*pi))
       x(i,1) = psi
       shap = decas(bzdeg, al, psi)
       y(i,1) = shap * psi**N1 * (1.0D0 - psi)**N2 + psi * zite_l
      ENDDO

C     Upper surface
      DO i=nle+1,nteu-1
       ang= REAL(i-nle)*teclust*pi/REAL(nteu-nle)
       psi = (1.D0-COS(ang))/(1.D0-COS(teclust*pi))
       x(i,1) = psi
       shap = decas(bzdeg, au, psi)
       y(i,1) = shap * psi**N1 * (1.0d0 - psi)**N2 + psi * zite_u
      ENDDO


C --- define points on other boundaries ---------------------------------------
C     boundary i=1 & i=ip / j=2,jp
C     (outflow plane)

      WRITE(*,'(A)') ' Distributing points on boundaries ...'

      CALL Stretch( dywk,ffdist,ny,sr )
      x( 1, 1) = 1.D0 + ffdist
      y( 1, 1) = 0.D0
      x(ip, 1) = 1.D0 + ffdist
      y(ip, 1) = 0.D0
      x( 1,jp) = 1.D0 + ffdist
      y( 1,jp) = -ffdist
      x(ip,jp) = 1.D0 + ffdist
      y(ip,jp) = ffdist
      dy       = dywk
      DO j=2,jp-1
        x( 1,j) = 1.D0 + ffdist
        y( 1,j) = y(1,j-1) - dy
        x(ip,j) = x(1,j)
        y(ip,j) = -y(1,j)
        dy      = sr*dy
      ENDDO

C --- boundary i=2,ntel-1 & i=nteu+1,ip / j=1 & j=jp
C     (wake line, farfield above wake)
C     -------------------------WARNING-----------------------------------
C     We are fitting a cubic curve to define the wake from TE to farfield
C     There is a small error in y value at farfield. Above it is assumed
C     that y(1,1) = 0.0 but the cubic curve does not satisfy this. But
C     the error is small if zite_l is small

      thetal = datan2( y(ntel,1)-y(ntel+1,1), x(ntel,1)-x(ntel+1,1) )
      thetau = datan2( y(nteu,1)-y(nteu-1,1), x(nteu,1)-x(nteu-1,1) )
      thetate= 0.5d0*( thetal + thetau)

      CALL Stretch( dxte,ffdist,nxw,sr )
      x(nteu,jp) = 1.D0
      y(nteu,jp) = ffdist
      x(ntel,jp) = 1.D0
      y(ntel,jp) = -ffdist
      dx         = dxte
      DO i=ntel-1,2,-1
        ii       = nteu + ntel - i      ! upper side
        x( i, 1) = x(i+1,1) + dx
        x( i,jp) = x(i,1)
        x(ii, 1) = x(i,1)
        x(ii,jp) = x(i,1)
        xi = (x(i,1) - 1.0d0)/(1.0d0+ffdist)
        y( i, 1) = zite_l+(1.0d0+ffdist)*dtan(thetate)*xi*(1.0d0-xi)**2
        y( i,jp) = -ffdist
        y(ii, 1) = y(i,1)
        y(ii,jp) =  ffdist
        dx       = sr*dx
      ENDDO

C --- boundary i=nle / j=2,jp
C     (line from l.e. to farfield)

      CALL Stretch( dyle,ffdist,ny,sr )
      dy = dyle
      DO j=2,jp
        x(nle,j) = x(nle,j-1) - dy
        y(nle,j) = 0.D0
        dy       = sr*dy
      ENDDO
      x(nle,jp) = -ffdist

C --- boundary i=ntel,nle & i=nle,nteu / j=jp
C     (farfield over the airfoil)

      xcirc = 0.25D0                 ! circular arc up to 25% chord
      a     = xcirc + ffdist

      i1  = ntel + 2
      i2  = nle  - 2
      ang = 0.5D0*pi/REAL(nle-ntel)
      dxe = a*(1.D0-COS(ang))
      x1  = ffdist + 1.D0 - 2.D0*dxte
      x2  = a*(1.D0-COS(2.D0*ang))
      CALL Sstretch( ntel,i1,i2,nle,ffdist+1.D0,x1,x2,0.D0,
     &               -dxte,-dxe,s4 )
      DO i=ntel+1,nle-1
        x(i,jp) = s4(i) - ffdist
        IF (x(i,jp) .LT. xcirc) THEN
          y(i,jp) = -ffdist*SQRT(1.D0-(x(i,jp)-xcirc)**2/a**2)
        ELSE
          y(i,jp) = -ffdist
        ENDIF
      ENDDO

      i1  = nle  + 2
      i2  = nteu - 2
      ang = 0.5D0*pi/REAL(nteu-nle)
      dxs = a*(1.D0-COS(ang))
      x1  = a*(1.D0-COS(2.D0*ang))
      x2  = ffdist + 1.D0 - 2.D0*dxte
      CALL Sstretch( nle,i1,i2,nteu,0.D0,x1,x2,ffdist+1.D0,
     &               dxs,dxte,s4 )
      DO i=nle+1,nteu-1
        x(i,jp) = s4(i) - ffdist
        IF (x(i,jp) .LT. xcirc) THEN
          y(i,jp) = ffdist*SQRT(1.D0-(x(i,jp)-xcirc)**2/a**2)
        ELSE
          y(i,jp) = ffdist
        ENDIF
      ENDDO

C --- internal grid points ----------------------------------------------------

      WRITE(*,'(A)') ' Generating interior grid ...'

      CALL Tfint( im,jm,  1,nle,1,jp,s1,s2,s3,s4,x,y )

      CALL Tfint( im,jm,nle,ip ,1,jp,s1,s2,s3,s4,x,y )

C --- smooth grid -------------------------------------------------------------

      WRITE(*,'(A)') ' Smoothing grid ...'

      icd = 00    ! spacing (icd,jcd) and angles (ica,jca) prescribed
      jcd = 11    ! at j=1 and j=jp
      ica = 00
      jca = 11

C --- wake and wall spacing in normal direction

      dy = dywk - dyte
      DO i=1,ntel
        s1(i) = dyte + dy*(x(i,1)-x(ntel,1))/(x(1,1)-x(ntel,1))
      ENDDO
      dy = dyte - dyle
      DO i=ntel+1,nle
        s1(i) = dyle + dy*(x(i,1)-x(nle,1))/(x(ntel,1)-x(nle,1))
      ENDDO
      dy = dyte - dyle
      DO i=nle+1,nteu-1
        s1(i) = dyle + dy*(x(i,1)-x(nle,1))/(x(nteu,1)-x(nle,1))
      ENDDO
      dy = dywk - dyte
      DO i=nteu,ip
        s1(i) = dyte + dy*(x(i,1)-x(nteu,1))/(x(ip,1)-x(nteu,1))
      ENDDO

      dx = x(1,jp-1) - x(1,jp)    ! same distance as
      dy = y(1,jp-1) - y(1,jp)    ! at outflow plane
      d  = SQRT(dx*dx+dy*dy)
      DO i=1,ip
        distes(i,1)  = s1(i)
        distes(i,jp) = d
      ENDDO

C --- grid lines normal to wall and farfield

      DO i=1,ip
        angles(i, 1) = 0.5D0*pi
        angles(i,jp) = 0.5D0*pi
      ENDDO

C --- elliptic grid smoothing

      CALL Ellgrid( im,jm,ip,jp,x,y,
     &              icd,jcd,ica,jca,
     &              itlapla,itsmoo,itgauss,
     &              damps,damps,pspace,1.D0,
     &              dampa,dampa,pangle,1.D0,
     &              omega,p,q,distes,angles )



C --- store and print ---------------------------------------------------------

      nc = Length(title)

C --- write out grid

      WRITE(*,'(A)') ' Saving grid file ...'

c     OPEN(10,FILE=fn_grid,FORM='formatted',STATUS='unknown')
c     WRITE(10,1010) title(1:nc),ip-1,jp-1
c     WRITE(10,1015) ((x(i,j),y(i,j), i=1,ip), j=1,jp)
c     Save grid in plot3d format
      OPEN(10,FILE=trim(fn_grid),STATUS='unknown')
      WRITE(10,*) ip,jp
      WRITE(10,*) ((x(i,j),i=1,ip), j=1,jp)
      WRITE(10,*) ((y(i,j), i=1,ip), j=1,jp)
      CLOSE(10)

C --- write out topology

      WRITE(*,'(A)') ' Saving topology file ...'

      OPEN(20,FILE=trim(fn_gtop),FORM='formatted',STATUS='unknown')
      WRITE(20,1020) title(1:nc),6,ip-1,jp-1
      WRITE(20,1025) 'cut 1'   ,700,1,2     ,ntel,1,ip  ,nteu+1
      WRITE(20,1025) 'wall'    ,300,1,ntel+1,nteu,0,0   ,0
      WRITE(20,1025) 'cut 2'   ,700,1,nteu+1,ip  ,1,ntel,2
      WRITE(20,1025) 'farfield',600,2,2     ,jp  ,0,0   ,0
      WRITE(20,1025) 'farfield',600,3,2     ,ip  ,0,0   ,0
      WRITE(20,1025) 'farfield',600,4,2     ,jp  ,0,0   ,0
      CLOSE(20)

C --- plot file

      WRITE(*,'(A)') ' Saving plot file ...'

      OPEN(30,FILE=trim(fn_plot),FORM='formatted',STATUS='unknown')
      WRITE(30,1045) title(1:nc),ip,jp
      DO j=1,jp
        DO i=1,ip
          WRITE(30,1035) x(i,j),y(i,j)
        ENDDO
      ENDDO
      WRITE(30,1050) ncoo
      DO i=1,ncoo
        WRITE(30,1035) xya(1,i),xya(2,i)
      ENDDO
      CLOSE(30)

      WRITE(*,'(/,A,/)') ' Finished.'



1000  FORMAT(' Number of grid points  : ',I3,' x ',I3,/,
     &       ' Leading edge index     : ',I3,/,
     &       ' T.e. ind. - lower surf.: ',I3,/,
     &       '           - upper surf.: ',I3,/)
1010  FORMAT('# ',A,/,'#',/,'# no. of cells in i-, j-direction',/,
     &       I6,2X,I6,/,'# coordinates (x, y):')
1015  FORMAT(2E17.9)
1020  FORMAT('# ',A,/,'#',/,'# no. of segments',/,I6,/,'#',/,
     &       '# no. of cells in i-, j-direction',/,I6,I6,/,'#',/,
     &       '# segments (cell-centred index!):',/,'#',/,
     &       '# itype lb  lbeg  lend  lbs  lbegs  lends',/,'#')
1025  FORMAT('# ',A,/,I6,I4,I6,I6,I5,2I7)
1035  FORMAT(2E17.9)
1045  FORMAT('1 0',/,A,/,'2',/,'2',/,'x',/,'y',/,
     &       I4,I4,' 0 0',/,'grid',/,'0 0 0')
1050  FORMAT(I4,' 1 0 0',/,'orig. airfoil',/,'0 0 0')
9999  STOP     
      end